#import <FBSDKCoreKit/FBSDKCoreKit.h>
#import <FBSDKLoginKit/FBSDKLoginKit.h>
#import <React/RCTBridge.h>
#import <React/RCTEventDispatcher.h>
#import <React/RCTLog.h>

#import "RCTFBLogin.h"
#import "RCTFBLoginManager.h"

@implementation RCTMFBLoginManager
    {
        RCTMFBLogin *_fbLogin;
        NSArray *_defaultPermissions;
        NSNumber *_loginBehavior;
    }
    
    @synthesize bridge = _bridge;
    
- (UIView *)view
    {
        _fbLogin = [[RCTMFBLogin alloc] init];
        _defaultPermissions = @[@"email"];
        _loginBehavior = FBSDKLoginBehaviorNative;
        
        [_fbLogin setPermissions:_defaultPermissions];
        [_fbLogin setLoginBehavior:_loginBehavior];
        [_fbLogin setDelegate:self];
        return _fbLogin;
    }
    
- (dispatch_queue_t)methodQueue
    {
        return dispatch_get_main_queue();
    }
    
    RCT_EXPORT_VIEW_PROPERTY(permissions, NSStringArray);
    RCT_EXPORT_VIEW_PROPERTY(loginBehavior, NSNumber);
    RCT_EXPORT_MODULE();
    
- (NSDictionary *)constantsToExport {
    return @{
             @"Events": @{
                     @"Login": @"FBLoginSuccessEvent",
                     @"LoginFound": @"FBLoginLoginFoundEvent",
                     @"Logout": @"FBLoginLogoutEvent",
                     @"Error": @"FBLoginErrorEvent",
                     @"Cancel": @"FBLoginCancelEvent",
                     @"PermissionsMissing": @"FBLoginPermissionsMissingEvent",
                     @"LoginNotFound": @"FBLoginLoginNotFoundEvent"
                     },
             @"LoginBehaviors": @{
                     @"Web": [NSNumber numberWithInt:FBSDKLoginBehaviorWeb],
                     @"Browser": [NSNumber numberWithInt:FBSDKLoginBehaviorBrowser],
                     @"Native": [NSNumber numberWithInt:FBSDKLoginBehaviorNative],
                     @"SystemAccount": [NSNumber numberWithInt:FBSDKLoginBehaviorSystemAccount]
                     }
             };
}
    
- (BOOL)hasPermission:(NSString *)permission {
    return [[FBSDKAccessToken currentAccessToken] hasGranted:permission];
}
    
- (NSArray *)getMissingPermissions:(NSArray *)expectedPermissions {
    FBSDKAccessToken *token = [FBSDKAccessToken currentAccessToken];
    NSMutableSet *missingPermissions = [NSMutableSet setWithArray:expectedPermissions];
    
    if (token) {
        [missingPermissions minusSet:token.permissions];
    }
    
    return [missingPermissions allObjects];
}
    
    
- (NSDictionary *)buildCredentials {
    NSDictionary *credentials = nil;
    FBSDKAccessToken *token = [FBSDKAccessToken currentAccessToken];
    
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    NSLocale *enUSPOSIXLocale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    [dateFormatter setLocale:enUSPOSIXLocale];
    [dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssZZZZZ"];
    
    NSString *tokenExpirationDate = [dateFormatter stringFromDate:token.expirationDate];
    
    if (token) {
        credentials = @{
                        @"token" : token.tokenString,
                        @"tokenExpirationDate" : tokenExpirationDate,
                        @"userId" : token.userID,
                        @"permissions" : [token.permissions allObjects]
                        };
    }
    
    return credentials;
}
    
    // fireEvent: trigger events for listeners on javascript components (RCTDeviceEventEmitter.addListener)
- (void) fireEvent:(NSString *)event {
    [self fireEvent:event withData:nil];
}
    
- (void) fireEvent:(NSString *)event withData:(NSDictionary *)data {
    NSString *eventName = self.constantsToExport[@"Events"][event];
    [self.bridge.eventDispatcher sendDeviceEventWithName:eventName
                                                    body:[NSMutableDictionary dictionaryWithDictionary:data]];
}
    
    
    // FBSDKLoginButtonDelegate :: Login
- (void)  loginButton:(FBSDKLoginButton *)loginButton
didCompleteWithResult:(FBSDKLoginManagerLoginResult *)result
                error:(NSError *)error{
    if (error) {
        [self fireEvent:@"Error" withData:@{
                                            @"description": error.localizedDescription
                                            }];
    } else if (result.isCancelled) {
        [self fireEvent:@"Cancel"];
    } else {
        NSArray *permissions = [loginButton.readPermissions arrayByAddingObjectsFromArray:loginButton.publishPermissions];
        NSArray *missingPermissions = [self getMissingPermissions:permissions];
        NSArray *decliendPermissions = [result.declinedPermissions allObjects];
        NSDictionary *loginData = @{
                                    @"credentials": [self buildCredentials],
                                    @"missingPermissions": missingPermissions,
                                    @"declinedPermissions": decliendPermissions
                                    };
        
        [self fireEvent:@"Login" withData:loginData];
        
        if (missingPermissions.count > 0) {
            NSDictionary *permissionData = @{
                                             @"missingPermissions": missingPermissions,
                                             @"declinedPermissions": decliendPermissions
                                             };
            [self fireEvent:@"PermissionsMissing" withData:permissionData];
        }
    }
}
    
    // FBSDKLoginButtonDelegate :: Logout
- (void)loginButtonDidLogOut:(FBSDKLoginButton *)loginButton{
    [self fireEvent:@"Logout"];
}
    
    // Exposed native methods (FBLoginManager.<methodName>)
    RCT_EXPORT_METHOD(login:(RCTResponseSenderBlock)callback) {
        [self loginWithPermissions:_defaultPermissions callback:callback];
    }
    
    RCT_EXPORT_METHOD(loginWithPermissions:(NSArray *)permissions callback:(RCTResponseSenderBlock)callback) {
        
        // Detect current access and return if no new permissions requested
        NSDictionary *currentCredentials = [self buildCredentials];
        NSArray *missingPermissions = [self getMissingPermissions:permissions];
        if(currentCredentials && (missingPermissions.count == 0)) {
            NSDictionary *loginData = @{
                                        @"credentials": currentCredentials,
                                        @"missingPermissions": missingPermissions
                                        };
            [self fireEvent:@"LoginFound" withData:loginData];
            if(callback)
            callback(@[[NSNull null], loginData]);
            return;
        }
        
        // No existing access token or missing permissions
        FBSDKLoginManager *login = [[FBSDKLoginManager alloc] init];
        login.loginBehavior = [_loginBehavior unsignedIntValue];
        [login logInWithReadPermissions:permissions fromViewController:nil handler:^(FBSDKLoginManagerLoginResult *result, NSError *error) {
            if (error) {
                [self fireEvent:@"Error" withData:@{
                                                    @"description": error.localizedDescription
                                                    }];
                if(callback)
                callback(@[error.localizedDescription, [NSNull null]]);
            } else if (result.isCancelled) {
                [self fireEvent:@"Cancel"];
                if(callback)
                callback(@[@"Cancel", [NSNull null]]);
            } else {
                
                NSArray *missingPermissions = [self getMissingPermissions:permissions];
                NSArray *decliendPermissions = [result.declinedPermissions allObjects];
                
                if (missingPermissions.count > 0) {
                    NSDictionary *permissionData = @{
                                                     @"missingPermissions": missingPermissions,
                                                     @"declinedPermissions": decliendPermissions
                                                     };
                    [self fireEvent:@"PermissionsMissing" withData:permissionData];
                } else {
                    NSMutableDictionary* parameters = [NSMutableDictionary dictionary];
                    [parameters setValue:@"id, first_name, last_name, email" forKey:@"fields"];
                    
                    [[[FBSDKGraphRequest alloc] initWithGraphPath:@"me" parameters:parameters]
                     startWithCompletionHandler:^(FBSDKGraphRequestConnection *connection, id result, NSError *error) {
                         NSDictionary *profile = @{
                                                   @"first_name": result[@"first_name"],
                                                   @"last_name": result[@"last_name"],
                                                   @"email": result[@"email"],
                                                   @"id": result[@"id"]
                                                   };
                         NSError * err;
                         NSData *jsonData = [NSJSONSerialization dataWithJSONObject:profile
                                                                            options:NSJSONWritingPrettyPrinted
                                                                              error:&err];
                         NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                         NSDictionary *loginData = @{
                                                     @"credentials": [self buildCredentials],
                                                     @"missingPermissions": missingPermissions,
                                                     @"declinedPermissions": decliendPermissions,
                                                     @"profile": jsonString
                                                     };
                         
                         [self fireEvent:@"Login" withData:loginData];
                         if(callback) callback(@[[NSNull null], loginData]);
                     }];
                }
            }
        }];
    }
    
    RCT_EXPORT_METHOD(logout:(RCTResponseSenderBlock)callback) {
        FBSDKLoginManager *login = [[FBSDKLoginManager alloc] init];
        [login logOut];
        [self fireEvent:@"Logout"];
        if(callback)
        callback(@[[NSNull null], @"Logout"]);
    }
    
    RCT_EXPORT_METHOD(getCredentials:(RCTResponseSenderBlock)callback) {
        NSDictionary *credentials = [self buildCredentials];
        
        if(credentials) {
            NSDictionary *loginData = @{
                                        @"credentials": credentials
                                        };
            
            [self fireEvent:@"LoginFound" withData:loginData];
            if(callback)
            callback(@[[NSNull null], loginData]);
        } else {
            [self fireEvent:@"LoginNotFound"];
            if(callback)
            callback(@[@"LoginNotFound", [NSNull null]]);
        }
    }
    
    RCT_EXPORT_METHOD(setLoginBehavior:(NSNumber * _Nonnull)loginBehavior) {
        _loginBehavior = loginBehavior;
    }
    
    @end
