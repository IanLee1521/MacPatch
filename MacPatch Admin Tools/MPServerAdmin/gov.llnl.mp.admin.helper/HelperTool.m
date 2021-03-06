/*
     File: HelperTool.m
 Abstract: The main object in the helper tool.
  Version: 1.0
 
 Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple
 Inc. ("Apple") in consideration of your agreement to the following
 terms, and your use, installation, modification or redistribution of
 this Apple software constitutes acceptance of these terms.  If you do
 not agree with these terms, please do not use, install, modify or
 redistribute this Apple software.
 
 In consideration of your agreement to abide by the following terms, and
 subject to these terms, Apple grants you a personal, non-exclusive
 license, under Apple's copyrights in this original Apple software (the
 "Apple Software"), to use, reproduce, modify and redistribute the Apple
 Software, with or without modifications, in source and/or binary forms;
 provided that if you redistribute the Apple Software in its entirety and
 without modifications, you must retain this notice and the following
 text and disclaimers in all such redistributions of the Apple Software.
 Neither the name, trademarks, service marks or logos of Apple Inc. may
 be used to endorse or promote products derived from the Apple Software
 without specific prior written permission from Apple.  Except as
 expressly stated in this notice, no other rights or licenses, express or
 implied, are granted by Apple herein, including but not limited to any
 patent rights that may be infringed by your derivative works or by other
 works in which the Apple Software may be incorporated.
 
 The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
 MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
 THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
 FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
 OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.
 
 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
 MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
 AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
 STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.
 
 Copyright (C) 2013 Apple Inc. All Rights Reserved.
 
 */

#import "HelperTool.h"
#import "Constants.h"
#import "Common.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <errno.h>

#import "MPRsyncD.h"
#import "XMLDictionary.h"
#import <ServiceManagement/ServiceManagement.h>

#import "AHLaunchCtl.h"

#undef  ql_component
#define ql_component lcl_cHelper

@interface HelperTool () <NSXPCListenerDelegate, HelperToolProtocol>

@property (atomic, strong, readwrite) NSXPCListener *listener;

- (NSInteger)serviceStatusForServiceLabel:(NSString *)aLabel;

@end

@implementation HelperTool

- (id)init
{
    self = [super init];
    if (self != nil) {
        // Set up our XPC listener to handle requests on our Mach service.
        self->_listener = [[NSXPCListener alloc] initWithMachServiceName:kHelperToolMachServiceName];
        self->_listener.delegate = self;
    }
    return self;
}

- (void)run
{
    // Tell the XPC listener to start processing requests.

    [self.listener resume];
    
    // Run the run loop forever.
    
    [[NSRunLoop currentRunLoop] run];
}

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection
    // Called by our XPC listener when a new connection comes in.  We configure the connection
    // with our protocol and ourselves as the main object.
{
    assert(listener == self.listener);
    #pragma unused(listener)
    assert(newConnection != nil);

    newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(HelperToolProtocol)];
    newConnection.exportedObject = self;
    [newConnection resume];
    
    return YES;
}

- (NSError *)checkAuthorization:(NSData *)authData command:(SEL)command
    // Check that the client denoted by authData is allowed to run the specified command. 
    // authData is expected to be an NSData with an AuthorizationExternalForm embedded inside.
{
    #pragma unused(authData)
    NSError *                   error;
    OSStatus                    err;
    OSStatus                    junk;
    AuthorizationRef            authRef;

    assert(command != nil);
    
    authRef = NULL;

    // First check that authData looks reasonable.
    
    error = nil;
    if ( (authData == nil) || ([authData length] != sizeof(AuthorizationExternalForm)) ) {
        error = [NSError errorWithDomain:NSOSStatusErrorDomain code:paramErr userInfo:nil];
    }
    
    // Create an authorization ref from that the external form data contained within.
    
    if (error == nil) {
        err = AuthorizationCreateFromExternalForm([authData bytes], &authRef);
        
        // Authorize the right associated with the command.
        
        if (err == errAuthorizationSuccess) {
            AuthorizationItem   oneRight = { NULL, 0, NULL, 0 };
            AuthorizationRights rights   = { 1, &oneRight };

            oneRight.name = [[Common authorizationRightForCommand:command] UTF8String];
            assert(oneRight.name != NULL);
            
            err = AuthorizationCopyRights(
                authRef,
                &rights,
                NULL,
                kAuthorizationFlagExtendRights | kAuthorizationFlagInteractionAllowed,
                NULL
            );
        }
        if (err != errAuthorizationSuccess) {
            error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
        }
    }

    if (authRef != NULL) {
        junk = AuthorizationFree(authRef, 0);
        assert(junk == errAuthorizationSuccess);
    }

    return error;
}

- (BOOL)isValidLicenseKey:(NSString *)licenseKey
    // Check that the license key is valid.  There are two things to note here.  The first 
    // is that I could have just passed an NSUUID across the NSXPCConnection, because 
    // NSUUID supports the NSSecureCoding protocol.  I didn't do that, however, because 
    // I wanted to make an important point, and that brings us to our second thing.  When 
    // you're writing a privileged helper tool you have to make sure that all the data 
    // passed to you from the client is valid.  NSXPCConnection does a lot of checking of 
    // this for you, but you still have to check your app-specific requirements.
    //
    // In this case the app-specific requirements are very simple--is the value not nil and 
    // can it be parsed as a UUID string--but in a complex app they might be a lot more complex.  
    // Regardless, it's vital that you do this checking for all data coming from untrusted 
    // sources.
{
    BOOL        success;
    NSUUID *    uuid;
    
    success = (licenseKey != nil);
    if (success) {
        uuid = [[NSUUID alloc] initWithUUIDString:licenseKey];
        success = (uuid != nil);
    }
    
    return success;
}

#pragma mark * HelperToolProtocol implementation

// IMPORTANT: NSXPCConnection can call these methods on any thread.  It turns out that our 
// implementation of these methods is thread safe but if that's not the case for your code 
// you have to implement your own protection (for example, having your own serial queue and 
// dispatching over to it).

- (void)connectWithEndpointReply:(void (^)(NSXPCListenerEndpoint *))reply
    // Part of the HelperToolProtocol.  Not used by the standard app (it's part of the sandboxed 
    // XPC service support).  Called by the XPC service to get an endpoint for our listener.  It then 
    // passes this endpoint to the app so that the sandboxed app can talk us directly.
{
    reply([self.listener endpoint]);
}

- (void)getVersionWithReply:(void(^)(NSString * version))reply
    // Part of the HelperToolProtocol.  Returns the version number of the tool.  Note that never
    // requires authorization.
{
    // We specifically don't check for authorization here.  Everyone is always allowed to get
    // the version of the helper tool.
    reply([[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]);
}

static NSString * kLicenseKeyDefaultsKey = @"licenseKey";

- (void)readLicenseKeyAuthorization:(NSData *)authData withReply:(void(^)(NSError * error, NSString * licenseKey))reply
    // Part of the HelperToolProtocol.  Gets the current license key from the defaults database.
{
    NSString *  licenseKey;
    NSError *   error;
    
    error = [self checkAuthorization:authData command:_cmd];
    if (error == nil) {
        licenseKey = [[NSUserDefaults standardUserDefaults] stringForKey:kLicenseKeyDefaultsKey];
    } else {
        licenseKey = nil;
    }

    reply(error, licenseKey);
}

- (void)writeLicenseKey:(NSString *)licenseKey authorization:(NSData *)authData withReply:(void(^)(NSError * error))reply
    // Part of the HelperToolProtocol.  Saves the license key to the defaults database.
{
    NSError *   error;
    
    error = nil;
    if ( ! [self isValidLicenseKey:licenseKey] ) {
        error = [NSError errorWithDomain:NSOSStatusErrorDomain code:paramErr userInfo:nil];
    }
    if (error == nil) {
        error = [self checkAuthorization:authData command:_cmd];
    }
    if (error == nil) {
        [[NSUserDefaults standardUserDefaults] setObject:licenseKey forKey:kLicenseKeyDefaultsKey];
    }

    reply(error);
}

#pragma mark - MacPatch

#pragma mark TOMCAT Server
// TomcatService
- (void)startTomcatServer:(NSData *)authData startOnBoot:(NSInteger)isStart withReply:(void(^)(NSError * error, NSString * licenseKey))reply
{
    
    AHLaunchJob *_job = [[AHLaunchJob alloc] init];
    NSLog(@"Check initialization. %@", _job);
    
    _job = [AHLaunchJob new];
    _job.Label = @"gov.llnl.mp.tomcat";
    _job.ProgramArguments = @[ @"/Library/MacPatch/Server/apache-tomcat/bin/launchdTomcat.sh" ];
    _job.EnvironmentVariables = @{ @"CATALINA_HOME": @"/Library/MacPatch/Server/apache-tomcat" };
    _job.StandardOutPath = @"/Library/MacPatch/Server/apache-tomcat/logs/stdout.log";
    _job.StandardErrorPath = @"/Library/MacPatch/Server/apache-tomcat/logs/stderr.log";
    _job.UserName = @"_appserver";
    _job.WorkingDirectory = @"/Library/MacPatch/Server/apache-tomcat";
    _job.RunAtLoad = YES;
    
    NSLog(@"Check initialization after property set. %@", _job);
    
    NSError *error = nil;
    if (![[AHLaunchCtl sharedController] add:_job toDomain:kAHGlobalLaunchDaemon error:&error]) {
        NSLog(@"Error Adding Job: %@", error.localizedDescription);
    }
    
    
    NSString *licenseKey = @"OK KEY";
    //NSError *error = nil;
    reply(error, licenseKey);
}

- (void)stopTomcatServer:(NSData *)authData startOnBoot:(NSInteger)isStart withReply:(void(^)(NSError * error, NSString * licenseKey))reply
{
    
    AHLaunchJob *_job = [[AHLaunchJob alloc] init];
    NSLog(@"Check initialization. %@", _job);
    
    _job = [AHLaunchJob new];
    _job.Label = @"gov.llnl.mp.tomcat";
    _job.ProgramArguments = @[ @"/Library/MacPatch/Server/apache-tomcat/bin/launchdTomcat.sh" ];
    _job.EnvironmentVariables = @{ @"CATALINA_HOME": @"/Library/MacPatch/Server/apache-tomcat" };
    _job.StandardOutPath = @"/Library/MacPatch/Server/apache-tomcat/logs/stdout.log";
    _job.StandardErrorPath = @"/Library/MacPatch/Server/apache-tomcat/logs/stderr.log";
    _job.UserName = @"_appserver";
    _job.WorkingDirectory = @"/Library/MacPatch/Server/apache-tomcat";
    _job.RunAtLoad = YES;
    
    NSLog(@"Check initialization after property set. %@", _job);
    
    NSError *error = nil;
    if (![[AHLaunchCtl sharedController] unload:_job.Label inDomain:kAHGlobalLaunchDaemon error:&error]) {
        NSLog(@"Error Removing Job: %@", error.localizedDescription);
    }
    
    NSString *licenseKey = @"OK KEY";
    //NSError *error = nil;
    reply(error, licenseKey);
}

- (void)toggleConsoleApp:(NSData *)authData startOnBoot:(NSInteger)isStart withReply:(void(^)(NSError * error, NSString * licenseKey))reply
{
    NSError *err = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:SITE_CONFIG])
    {
        NSMutableDictionary *scf = [[NSMutableDictionary dictionaryWithDictionary:[self readSiteConfig:SITE_CONFIG error:&err]] mutableCopy];
        if (err) {
            reply(err, @"");
            return;
        }
        // Set Production Data
        NSMutableDictionary *tcSrvcDict = [NSMutableDictionary dictionaryWithDictionary:[scf valueForKeyPath:@"settings.services"]];
        if ([[tcSrvcDict objectForKey:@"console"] boolValue] == YES) {
            scf[@"settings"][@"services"][@"console"] = [NSNumber numberWithBool:NO];
        } else {
            scf[@"settings"][@"services"][@"console"] = [NSNumber numberWithBool:YES];
        }
        
        // Write Site Config Back Out
        err = nil;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:scf options:NSJSONWritingPrettyPrinted error:&err];
        
        // Stuping fix for NSJSONSerialization escaping paths
        NSString *jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        jsonStr = [jsonStr stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"];
        jsonData = [jsonStr dataUsingEncoding:NSUTF8StringEncoding];
        
        [jsonData writeToFile:SITE_CONFIG options:0 error:&err];
        if (err) {
            reply(err, @"");
            return;
        }
        
    }
    else
    {
        NSMutableDictionary* details = [NSMutableDictionary dictionary];
        [details setValue:[NSString stringWithFormat:@"[writeDBConf]: file not found %@",SITE_CONFIG] forKey:NSLocalizedDescriptionKey];
        err = [NSError errorWithDomain:NSCocoaErrorDomain code:1003 userInfo:details];
    }
    
    reply(err, @"");
}

- (void)toggleWebServiceApp:(NSData *)authData startOnBoot:(NSInteger)isStart withReply:(void(^)(NSError * error, NSString * licenseKey))reply
{
    NSError *err = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:SITE_CONFIG])
    {
        NSMutableDictionary *scf = [[NSMutableDictionary dictionaryWithDictionary:[self readSiteConfig:SITE_CONFIG error:&err]] mutableCopy];
        if (err) {
            reply(err, @"");
            return;
        }
        // Set Production Data
        NSMutableDictionary *tcSrvcDict = [NSMutableDictionary dictionaryWithDictionary:[scf valueForKeyPath:@"settings.services"]];
        if ([[tcSrvcDict objectForKey:@"mpwsl"] boolValue] == YES) {
            scf[@"settings"][@"services"][@"mpwsl"] = [NSNumber numberWithBool:NO];
        } else {
            scf[@"settings"][@"services"][@"mpwsl"] = [NSNumber numberWithBool:YES];
        }
        
        // Write Site Config Back Out
        err = nil;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:scf options:NSJSONWritingPrettyPrinted error:&err];
        
        // Stuping fix for NSJSONSerialization escaping paths
        NSString *jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        jsonStr = [jsonStr stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"];
        jsonData = [jsonStr dataUsingEncoding:NSUTF8StringEncoding];
        
        [jsonData writeToFile:SITE_CONFIG options:0 error:&err];
        if (err) {
            reply(err, @"");
            return;
        }
        
    }
    else
    {
        NSMutableDictionary* details = [NSMutableDictionary dictionary];
        [details setValue:[NSString stringWithFormat:@"[writeDBConf]: file not found %@",SITE_CONFIG] forKey:NSLocalizedDescriptionKey];
        err = [NSError errorWithDomain:NSCocoaErrorDomain code:1003 userInfo:details];
    }
    
    reply(err, @"");
}

#pragma mark WEB Server
// Depricated with 2.8.x
- (void)startWebServer:(NSData *)authData startOnBoot:(NSInteger)isStart withReply:(void(^)(NSError * error, NSString * licenseKey))reply __deprecated
{
    NSLog(@"Called start Web Server");
    
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:LAUNCHD_FILE_WEBSERVER])
    {
        qltrace(@"File Does Not Exist %@",LAUNCHD_FILE_WEBSERVER);
        
        NSError *err = nil;
        [fm copyItemAtPath:LAUNCHD_ORIG_WEBSERVER toPath:LAUNCHD_FILE_WEBSERVER error:&err];
        if (err) {
            qlerror(@"%@",err.localizedDescription);
            NSLog(@"Error: %@",err.localizedDescription);
            return;
        }
        
        // Permissions and Ownership
        //[self setLaunchDFilePermissions:LAUNCHD_FILE_WEBSERVER];
        
        // Load the file
        qldebug(@"/bin/launchctl args: %@",[NSArray arrayWithObjects:@"load",LAUNCHD_FILE_WEBSERVER, nil]);
        [NSTask launchedTaskWithLaunchPath:@"/bin/launchctl" arguments:[NSArray arrayWithObjects:@"load",LAUNCHD_FILE_WEBSERVER, nil]];
    }
    
    // Permissions and Ownership
    //[self setLaunchDFilePermissions:LAUNCHD_FILE_WEBSERVER];
    
    // Set RunAtLoad value
    NSMutableDictionary *md = [NSMutableDictionary dictionaryWithContentsOfFile:LAUNCHD_FILE_WEBSERVER];
    if (isStart > 0)
    {
        [NSTask launchedTaskWithLaunchPath:@"/usr/bin/defaults" arguments:[NSArray arrayWithObjects:@"write",LAUNCHD_FILE_WEBSERVER, @"RunAtLoad", @"-bool",@"YES", nil]];
    } else {
        [NSTask launchedTaskWithLaunchPath:@"/usr/bin/defaults" arguments:[NSArray arrayWithObjects:@"write",LAUNCHD_FILE_WEBSERVER, @"RunAtLoad", @"-bool",@"NO", nil]];
    }
    // Write the changes
    [md writeToFile:LAUNCHD_FILE_WEBSERVER atomically:NO];
    
    
    NSString *licenseKey = @"START WEB SERVER";
    NSError *error = nil;
    [NSTask launchedTaskWithLaunchPath:@"/bin/launchctl" arguments:[NSArray arrayWithObjects:@"start",SERVICE_WEBSERVER, nil]];
    
    reply(error, licenseKey);
}

// Depricated with 2.8.x
- (void)stopWebServer:(NSData *)authData startOnBoot:(NSInteger)isStart withReply:(void(^)(NSError * error, NSString * licenseKey))reply __deprecated
{
    NSString *licenseKey = @"Called stop Web Server";
    NSError *error = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    
    if (![fm fileExistsAtPath:LAUNCHD_FILE_WEBSERVER]) {
        reply(error, licenseKey);
        return;
    }
    
    // Set RunAtLoad value
    NSMutableDictionary *md = [NSMutableDictionary dictionaryWithContentsOfFile:LAUNCHD_FILE_WEBSERVER];
    if (isStart > 0)
    {
        [NSTask launchedTaskWithLaunchPath:@"/usr/bin/defaults" arguments:[NSArray arrayWithObjects:@"write",LAUNCHD_FILE_WEBSERVER, @"RunAtLoad", @"-bool",@"YES", nil]];
    } else {
        [NSTask launchedTaskWithLaunchPath:@"/usr/bin/defaults" arguments:[NSArray arrayWithObjects:@"write",LAUNCHD_FILE_WEBSERVER, @"RunAtLoad", @"-bool",@"NO", nil]];
    }
    // Write the changes
    [md writeToFile:LAUNCHD_FILE_WEBSERVER atomically:NO];
    
    [NSTask launchedTaskWithLaunchPath:@"/bin/launchctl" arguments:[NSArray arrayWithObjects:@"stop",SERVICE_WEBSERVER, nil]];
    
    reply(error, licenseKey);
}

#pragma mark Admin Service
// Depricated with 2.8.x
- (void)startService:(NSData *)authData startOnBoot:(NSInteger)isStart withReply:(void(^)(NSError * error, NSString * licenseKey))reply __deprecated
{
    //NSLog(@"Called start service");
    
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:LAUNCHD_FILE])
    {
        NSError *err = nil;
        [fm copyItemAtPath:LAUNCHD_ORIG toPath:LAUNCHD_FILE error:&err];
        if (err) {
            NSLog(@"Error: %@",err.localizedDescription);
            return;
        }
        
        // Permissions and Ownership
        //[self setLaunchDFilePermissions:LAUNCHD_FILE];
        
        // Load the file
        [NSTask launchedTaskWithLaunchPath:@"/bin/launchctl" arguments:[NSArray arrayWithObjects:@"load",LAUNCHD_FILE, nil]];
    }
    
    // Permissions and Ownership
    //[self setLaunchDFilePermissions:LAUNCHD_FILE];
    
    // Set RunAtLoad value
    NSMutableDictionary *md = [NSMutableDictionary dictionaryWithContentsOfFile:LAUNCHD_FILE];
    if (isStart > 0)
    {
        [NSTask launchedTaskWithLaunchPath:@"/usr/bin/defaults" arguments:[NSArray arrayWithObjects:@"write",LAUNCHD_FILE, @"RunAtLoad", @"-bool",@"YES", nil]];
    } else {
        [NSTask launchedTaskWithLaunchPath:@"/usr/bin/defaults" arguments:[NSArray arrayWithObjects:@"write",LAUNCHD_FILE, @"RunAtLoad", @"-bool",@"NO", nil]];
    }
    // Write the changes
    [md writeToFile:LAUNCHD_FILE atomically:NO];
    
    
    NSString *licenseKey = @"OK KEY";
    NSError *error = nil;
    [NSTask launchedTaskWithLaunchPath:@"/bin/launchctl" arguments:[NSArray arrayWithObjects:@"start",SERVICE, nil]];
    
    reply(error, licenseKey);
}

// Depricated with 2.8.x
- (void)stopService:(NSData *)authData startOnBoot:(NSInteger)isStart withReply:(void(^)(NSError * error, NSString * licenseKey))reply __deprecated
{
    NSString *licenseKey = @"STOP KEY";
    NSError *error = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    
    if (![fm fileExistsAtPath:LAUNCHD_FILE]) {
        reply(error, licenseKey);
        return;
    }
    
    // Set RunAtLoad value
    // NSMutableDictionary *md = [NSMutableDictionary dictionaryWithContentsOfFile:LAUNCHD_FILE];
    if (isStart > 0)
    {
        [NSTask launchedTaskWithLaunchPath:@"/usr/bin/defaults" arguments:[NSArray arrayWithObjects:@"write",LAUNCHD_FILE, @"RunAtLoad", @"-bool",@"YES", nil]];
    } else {
        [NSTask launchedTaskWithLaunchPath:@"/usr/bin/defaults" arguments:[NSArray arrayWithObjects:@"write",LAUNCHD_FILE, @"RunAtLoad", @"-bool",@"NO", nil]];
    }
    // Write the changes
    // [md writeToFile:LAUNCHD_FILE atomically:NO];
    
    [NSTask launchedTaskWithLaunchPath:@"/bin/launchctl" arguments:[NSArray arrayWithObjects:@"stop", SERVICE, nil]];
    
    reply(error, licenseKey);
}

// Depricated with 2.8.x
- (void)readSiteData:(NSData *)authData withReply:(void(^)(NSError * error, NSDictionary * siteDict))reply
{
    NSString        *sitePort = @"2601";
    NSError         *error = nil;
    
    NSString *xmlString = [[NSString alloc] initWithContentsOfFile:TOMCAT_ADMIN_CONF encoding:NSUTF8StringEncoding error:&error];
    NSDictionary *xmlDoc = [NSDictionary dictionaryWithXMLString:xmlString];
    sitePort = [[[xmlDoc valueForKeyPath:@"Service.Connector"] objectAtIndex:0] objectForKey:@"_port"];
    
    NSDictionary *md = @{@"port":sitePort};
    reply(error, md);
}

// Depricated with 2.8.x
- (void)writeSiteConfig:(NSData *)authData siteConf:(NSDictionary *)siteDict launchDConf:(NSDictionary *)launchDConf withReply:(void(^)(NSError * error, NSString * licenseKey))reply __deprecated
{
    NSError *err = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    
    // Read the current XML Doc & create a Mutable Dictionary
    NSString *xmlString = [[NSString alloc] initWithContentsOfFile:TOMCAT_ADMIN_CONF encoding:NSUTF8StringEncoding error:&err];
    NSMutableDictionary *md = [NSMutableDictionary dictionaryWithDictionary:[NSDictionary dictionaryWithXMLString:xmlString]];
    // Set the new port value
    [[[[md objectForKey:@"Service"] objectForKey:@"Connector"] objectAtIndex:0] setObject:[siteDict objectForKey:@"port"] forKey:@"_port"];
    // Write the new XML file to filesystem
    //NSMutableString *ms = [[NSMutableString alloc] initWithString:@"<?xml version='1.0' encoding='utf-8'?>"];
    //[ms appendString:[md XMLString]];
    //[ms writeToFile:TOMCAT_ADMIN_CONF atomically:NO encoding:NSUTF8StringEncoding error:&err];
    
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithXMLString:[md XMLString] options:NSXMLDocumentTidyXML error:NULL];
    NSString *xstr = [doc XMLStringWithOptions:NSXMLNodePrettyPrint];
    [xstr writeToFile:TOMCAT_ADMIN_CONF atomically:NO encoding:NSUTF8StringEncoding error:NULL];
    
    // Set LaunchD conf file settings
    NSString *launchDFile;
    if ([fm fileExistsAtPath:LAUNCHD_FILE])
    {
        launchDFile = LAUNCHD_FILE;
    } else {
        launchDFile = LAUNCHD_ORIG;
    }
    
    if ([fm fileExistsAtPath:launchDFile]) {
        NSMutableDictionary *d = [NSMutableDictionary dictionaryWithContentsOfFile:launchDFile];
        for (NSString *s in launchDConf.allKeys) {
            [d setObject:[launchDConf objectForKey:s] forKey:s];
        }
        
        [d writeToFile:launchDFile atomically:NO];
    } else {
        NSMutableDictionary* details = [NSMutableDictionary dictionary];
        [details setValue:[NSString stringWithFormat:@"Unable to write to file %@",launchDFile] forKey:NSLocalizedDescriptionKey];
        err = [NSError errorWithDomain:NSCocoaErrorDomain code:1003 userInfo:details];
    }
    
    reply(err, @"");
}

#pragma mark Web Services

// Depricated with 2.8.x
- (void)startWSService:(NSData *)authData startOnBoot:(NSInteger)isStart withReply:(void(^)(NSError * error, NSString * licenseKey))reply __deprecated
{
    //NSLog(@"Called start service");
    
    NSFileManager *fm = [NSFileManager defaultManager];
    
    // Web Service File
    if (![fm fileExistsAtPath:LAUNCHD_WS_FILE])
    {
        NSError *err = nil;
        [fm copyItemAtPath:LAUNCHD_WS_ORIG toPath:LAUNCHD_WS_FILE error:&err];
        if (err) {
            NSLog(@"Error: %@",err.localizedDescription);
            return;
        }
        
        // Permissions and Ownership
        //[self setLaunchDFilePermissions:LAUNCHD_WS_FILE];
        
        // Load the file
        [NSTask launchedTaskWithLaunchPath:@"/bin/launchctl" arguments:[NSArray arrayWithObjects:@"load",LAUNCHD_WS_FILE, nil]];
    }
    
    // Inv Service File
    if (![fm fileExistsAtPath:LAUNCHD_INV_FILE])
    {
        NSError *err = nil;
        [fm copyItemAtPath:LAUNCHD_INV_ORIG toPath:LAUNCHD_INV_FILE error:&err];
        if (err) {
            NSLog(@"Error: %@",err.localizedDescription);
            return;
        }
        
        // Permissions and Ownership
        //[self setLaunchDFilePermissions:LAUNCHD_INV_FILE];
        
        // Load the file
        [NSTask launchedTaskWithLaunchPath:@"/bin/launchctl" arguments:[NSArray arrayWithObjects:@"load",LAUNCHD_INV_FILE, nil]];
    }
    
    // Set RunAtLoad value
    if (isStart > 0)
    {
        if ([fm fileExistsAtPath:LAUNCHD_WS_FILE]) {
            [NSTask launchedTaskWithLaunchPath:@"/usr/bin/defaults" arguments:[NSArray arrayWithObjects:@"write",LAUNCHD_WS_FILE, @"RunAtLoad", @"-bool",@"YES", nil]];
        }
        if ([fm fileExistsAtPath:LAUNCHD_INV_FILE]) {
            [NSTask launchedTaskWithLaunchPath:@"/usr/bin/defaults" arguments:[NSArray arrayWithObjects:@"write",LAUNCHD_INV_FILE, @"RunAtLoad", @"-bool",@"YES", nil]];
        }
    } else {
        if ([fm fileExistsAtPath:LAUNCHD_WS_FILE]) {
            [NSTask launchedTaskWithLaunchPath:@"/usr/bin/defaults" arguments:[NSArray arrayWithObjects:@"write",LAUNCHD_WS_FILE, @"RunAtLoad", @"-bool",@"NO", nil]];
        }
        if ([fm fileExistsAtPath:LAUNCHD_INV_FILE]) {
            [NSTask launchedTaskWithLaunchPath:@"/usr/bin/defaults" arguments:[NSArray arrayWithObjects:@"write",LAUNCHD_INV_FILE, @"RunAtLoad", @"-bool",@"NO", nil]];
        }
    }
    
    NSString *licenseKey = @"OK KEY";
    NSError *error = nil;
    [NSTask launchedTaskWithLaunchPath:@"/bin/launchctl" arguments:[NSArray arrayWithObjects:@"start",SERVICE_WS, nil]];
    [NSTask launchedTaskWithLaunchPath:@"/bin/launchctl" arguments:[NSArray arrayWithObjects:@"start",SERVICE_INV, nil]];
    
    reply(error, licenseKey);
}

// Depricated with 2.8.x
- (void)stopWSService:(NSData *)authData startOnBoot:(NSInteger)isStart withReply:(void(^)(NSError * error, NSString * licenseKey))reply __deprecated
{
    NSString *licenseKey = @"STOP KEY";
    NSError *error = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    
    if (![fm fileExistsAtPath:LAUNCHD_WS_FILE] && ![fm fileExistsAtPath:LAUNCHD_INV_FILE]) {
        reply(error, licenseKey);
        return;
    }
    
    // Set RunAtLoad value
    //NSMutableDictionary *md = [NSMutableDictionary dictionaryWithContentsOfFile:LAUNCHD_WS_FILE];
    if (isStart > 0)
    {
        if ([fm fileExistsAtPath:LAUNCHD_WS_FILE]) {
            [NSTask launchedTaskWithLaunchPath:@"/usr/bin/defaults" arguments:[NSArray arrayWithObjects:@"write",LAUNCHD_WS_FILE, @"RunAtLoad", @"-bool",@"YES", nil]];
        }
        if ([fm fileExistsAtPath:LAUNCHD_INV_FILE]) {
            [NSTask launchedTaskWithLaunchPath:@"/usr/bin/defaults" arguments:[NSArray arrayWithObjects:@"write",LAUNCHD_INV_FILE, @"RunAtLoad", @"-bool",@"YES", nil]];
        }
    } else {
        if ([fm fileExistsAtPath:LAUNCHD_WS_FILE]) {
            [NSTask launchedTaskWithLaunchPath:@"/usr/bin/defaults" arguments:[NSArray arrayWithObjects:@"write",LAUNCHD_WS_FILE, @"RunAtLoad", @"-bool",@"NO", nil]];
        }
        if ([fm fileExistsAtPath:LAUNCHD_INV_FILE]) {
            [NSTask launchedTaskWithLaunchPath:@"/usr/bin/defaults" arguments:[NSArray arrayWithObjects:@"write",LAUNCHD_INV_FILE, @"RunAtLoad", @"-bool",@"NO", nil]];
        }
    }
    // Write the changes
    //[md writeToFile:LAUNCHD_WS_FILE atomically:NO];
    
    [NSTask launchedTaskWithLaunchPath:@"/bin/launchctl" arguments:[NSArray arrayWithObjects:@"stop",SERVICE_WS, nil]];
    [NSTask launchedTaskWithLaunchPath:@"/bin/launchctl" arguments:[NSArray arrayWithObjects:@"stop",SERVICE_INV, nil]];
    
    reply(error, licenseKey);
}

// Depricated with 2.8.x
- (void)readWSData:(NSData *)authData withReply:(void(^)(NSError * error, NSDictionary * siteDict))reply __deprecated
{
    NSString        *sitePort = @"2601";
    NSError         *error = nil;
    
    NSString *xmlString = [[NSString alloc] initWithContentsOfFile:TOMCAT_WS_CONF encoding:NSUTF8StringEncoding error:&error];
    NSDictionary *xmlDoc = [NSDictionary dictionaryWithXMLString:xmlString];
    sitePort = [[[xmlDoc valueForKeyPath:@"Service.Connector"] objectAtIndex:0] objectForKey:@"_port"];
    
    NSDictionary *md = @{@"port":sitePort};
    reply(error, md);
}

// Depricated with 2.8.x
- (void)writeWSConfig:(NSData *)authData siteConf:(NSDictionary *)siteDict launchDConf:(NSDictionary *)launchDConf withReply:(void(^)(NSError * error, NSString * licenseKey))reply __deprecated
{
    NSError *err = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    
    // Read the current XML Doc & create a Mutable Dictionary
    NSString *xmlString = [[NSString alloc] initWithContentsOfFile:TOMCAT_WS_CONF encoding:NSUTF8StringEncoding error:&err];
    NSMutableDictionary *md = [NSMutableDictionary dictionaryWithDictionary:[NSDictionary dictionaryWithXMLString:xmlString]];
    // Set the new port value
    [[[[md objectForKey:@"Service"] objectForKey:@"Connector"] objectAtIndex:0] setObject:[siteDict objectForKey:@"port"] forKey:@"_port"];
    // Write the new XML file to filesystem
    //NSMutableString *ms = [[NSMutableString alloc] initWithString:@"<?xml version='1.0' encoding='utf-8'?>"];
    //[ms appendString:[md XMLString]];
    //[ms writeToFile:TOMCAT_ADMIN_CONF atomically:NO encoding:NSUTF8StringEncoding error:&err];
    
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithXMLString:[md XMLString] options:NSXMLDocumentTidyXML error:NULL];
    NSString *xstr = [doc XMLStringWithOptions:NSXMLNodePrettyPrint];
    [xstr writeToFile:TOMCAT_WS_CONF atomically:NO encoding:NSUTF8StringEncoding error:NULL];
    
    // Set LaunchD conf file settings
    NSString *launchDFile;
    if ([fm fileExistsAtPath:LAUNCHD_FILE])
    {
        launchDFile = LAUNCHD_FILE;
    } else {
        launchDFile = LAUNCHD_ORIG;
    }
    
    if ([fm fileExistsAtPath:launchDFile]) {
        NSMutableDictionary *d = [NSMutableDictionary dictionaryWithContentsOfFile:launchDFile];
        for (NSString *s in launchDConf.allKeys) {
            [d setObject:[launchDConf objectForKey:s] forKey:s];
        }
        
        [d writeToFile:launchDFile atomically:NO];
    } else {
        NSMutableDictionary* details = [NSMutableDictionary dictionary];
        [details setValue:[NSString stringWithFormat:@"Unable to write to file %@",launchDFile] forKey:NSLocalizedDescriptionKey];
        err = [NSError errorWithDomain:NSCocoaErrorDomain code:1003 userInfo:details];
    }
    
    reply(err, @"");
}

#pragma mark Misc
- (void)readLaunchDFile:(NSString *)aFile withReply:(void(^)(NSDictionary *aDictionary))reply
{
    NSDictionary *md;
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:aFile]) {
        md = [NSDictionary dictionaryWithContentsOfFile:aFile];
    }

    reply(md);
}

- (NSInteger)serviceStatusForServiceLabel:(NSString *)aLabel
{
    // Status Codes
    // 0 = not running/not loaded
    // 1 = loaded/no PID
    // 2 = loaded and running
    NSArray *jobs = (__bridge NSArray *)SMCopyAllJobDictionaries(kSMDomainSystemLaunchd);
    if (!jobs) {
        return 0;
    }
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"Label CONTAINS[cd] %@", aLabel];
    NSArray *results = [jobs filteredArrayUsingPredicate:predicate];
    if ([results count] <= 0) {
        // No Results found
        return 0;
    }
    
    if ([[results objectAtIndex:0] objectForKey:@"PID"] == nil) {
        return 1;
    } else {
        if ([[[results objectAtIndex:0] objectForKey:@"PID"] integerValue] >= 1) {
            return 2;
        } else {
            return 1;
        }
    }
    
    return 0;
}

#pragma mark Apple Patch Sync

- (void)startSUSService:(NSData *)authData startOnBoot:(NSInteger)isStart withReply:(void(^)(NSError * error, NSString * licenseKey))reply
{
    NSDictionary *lDict;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:LAUNCHD_SUS_ORIG])
    {
        lDict = [NSDictionary dictionaryWithContentsOfFile:LAUNCHD_SUS_ORIG];
    } else {
        lDict = @{ @"Label" :  @"gov.llnl.mp.sus.sync",
                     @"ProgramArguments" :  @[ @"/Library/MacPatch/Server/conf/scripts/MPSUSPatchSync.py",
                                               @"--plist",
                                               @"/Library/MacPatch/Server/conf/etc/gov.llnl.mp.patchloader.plist"],
                     @"StandardOutPath": @"/Library/MacPatch/Server/Logs/MPSUSPatchSync_stdout.log",
                     @"StandardErrorPath": @"/Library/MacPatch/Server/Logs/MPSUSPatchSync_stderr.log",
                     @"StartInterval": @28800,
                     @"RunAtLoad": @YES
                     };
    }
    
    AHLaunchJob *_job = [[AHLaunchJob alloc] init];
    NSLog(@"Check initialization. %@", _job);
    
    _job = [AHLaunchJob new];
    _job.Label = lDict[@"Label"];
    _job.ProgramArguments = lDict[@"ProgramArguments"];
    _job.StandardOutPath = lDict[@"StandardOutPath"];
    _job.StandardErrorPath = lDict[@"StandardErrorPath"];
    _job.StartInterval = (NSInteger)lDict[@"StartInterval"];
    _job.RunAtLoad = (isStart > 0) ? YES : NO;
    
    NSError *error = nil;
    if (![[AHLaunchCtl sharedController] add:_job toDomain:kAHGlobalLaunchDaemon error:&error]) {
        NSLog(@"Error Adding Job: %@", error.localizedDescription);
    }
    
    NSString *licenseKey = @"START SUS Sync";
    reply(error, licenseKey);
}

- (void)stopSUSService:(NSData *)authData startOnBoot:(NSInteger)isStart withReply:(void(^)(NSError * error, NSString * licenseKey))reply
{
    NSDictionary *lDict;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:LAUNCHD_SUS_ORIG])
    {
        lDict = [NSDictionary dictionaryWithContentsOfFile:LAUNCHD_SUS_ORIG];
    } else {
        lDict = @{ @"Label" :  @"gov.llnl.mp.sus.sync",
                     @"ProgramArguments" :  @[ @"/Library/MacPatch/Server/conf/scripts/MPSUSPatchSync.py",
                                               @"--plist",
                                               @"/Library/MacPatch/Server/conf/etc/gov.llnl.mp.patchloader.plist"],
                     @"StandardOutPath": @"/Library/MacPatch/Server/Logs/MPSUSPatchSync_stdout.log",
                     @"StandardErrorPath": @"/Library/MacPatch/Server/Logs/MPSUSPatchSync_stderr.log",
                     @"StartInterval": @28800,
                     @"RunAtLoad": @NO
                     };
    }
    
    AHLaunchJob *_job = [[AHLaunchJob alloc] init];
    NSLog(@"Check initialization. %@", _job);
    
    _job = [AHLaunchJob new];
    _job.Label = lDict[@"Label"];
    _job.ProgramArguments = lDict[@"ProgramArguments"];
    _job.StandardOutPath = lDict[@"StandardOutPath"];
    _job.StandardErrorPath = lDict[@"StandardErrorPath"];
    _job.StartInterval = (NSInteger)lDict[@"StartInterval"];
    _job.RunAtLoad = (isStart > 0) ? YES : NO;
    
    NSError *error = nil;
    if (![[AHLaunchCtl sharedController] unload:_job.Label inDomain:kAHGlobalLaunchDaemon error:&error]) {
        NSLog(@"Error Removing Job: %@", error.localizedDescription);
    }
    
    NSString *licenseKey = @"STOP SUS Sync";
    reply(error, licenseKey);
}

- (void)readSUSConf:(NSData *)authData withReply:(void(^)(NSError * error, NSDictionary * susDict))reply
{
    NSError *err = nil;
    NSDictionary *md;
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:SERVICE_SUS_CONF_FILE]) {
        md = [NSDictionary dictionaryWithContentsOfFile:SERVICE_SUS_CONF_FILE];
    } else {
        NSMutableDictionary* details = [NSMutableDictionary dictionary];
        [details setValue:[NSString stringWithFormat:@"Error reading fine %@",SERVICE_SUS_CONF_FILE] forKey:NSLocalizedDescriptionKey];
        err = [NSError errorWithDomain:NSCocoaErrorDomain code:1001 userInfo:details];
    }
    
    reply(err, md);
}

- (void)writeSUSConf:(NSData *)authData susConf:(NSDictionary *)susDict launchDConf:(NSDictionary *)launchDConf withReply:(void(^)(NSError * error, NSString * licenseKey))reply
{
    NSError *err = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:SERVICE_SUS_CONF_FILE]) {
        [susDict writeToFile:SERVICE_SUS_CONF_FILE atomically:NO];
    } else {
        NSMutableDictionary* details = [NSMutableDictionary dictionary];
        [details setValue:[NSString stringWithFormat:@"Unable to write to file %@",SERVICE_SUS_CONF_FILE] forKey:NSLocalizedDescriptionKey];
        err = [NSError errorWithDomain:NSCocoaErrorDomain code:1002 userInfo:details];
    }
    
    NSString *launchDFile;
    if ([fm fileExistsAtPath:LAUNCHD_SUS_FILE])
    {
        launchDFile = LAUNCHD_SUS_FILE;
    } else {
        launchDFile = LAUNCHD_SUS_ORIG;
    }
    
    if ([fm fileExistsAtPath:launchDFile]) {
        NSMutableDictionary *d = [NSMutableDictionary dictionaryWithContentsOfFile:launchDFile];
        for (NSString *s in launchDConf.allKeys) {
            [d setObject:[launchDConf objectForKey:s] forKey:s];
        }
        
        [d writeToFile:launchDFile atomically:NO];
    } else {
        NSMutableDictionary* details = [NSMutableDictionary dictionary];
        [details setValue:[NSString stringWithFormat:@"Unable to write to file %@",launchDFile] forKey:NSLocalizedDescriptionKey];
        err = [NSError errorWithDomain:NSCocoaErrorDomain code:1003 userInfo:details];
    }
    
    reply(err, @"");
}

#pragma mark - MP Patch Sync

#pragma mark Sync From Master

- (void)startPatchSyncService:(NSData *)authData startOnBoot:(NSInteger)isStart withReply:(void(^)(NSError * error, NSString * licenseKey))reply
{
    NSDictionary *lDict;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:LAUNCHD_ORIG_PATCH_SYNC])
    {
        lDict = [NSDictionary dictionaryWithContentsOfFile:LAUNCHD_ORIG_PATCH_SYNC];
    } else {
        lDict = @{ @"Label" :  @"gov.llnl.mp.sync",
                     @"ProgramArguments" :  @[ @"/Library/MacPatch/Server/conf/scripts/MPSyncContent.py" ],
                     @"StandardOutPath": @"/Library/MacPatch/Server/Logs/mp_sync_stdout.log",
                     @"StandardErrorPath": @"/Library/MacPatch/Server/Logs/mp_sync_stderr.log",
                     @"StartInterval": @1800,
                     @"RunAtLoad": @YES
                     };
    }
    
    AHLaunchJob *_job = [[AHLaunchJob alloc] init];
    NSLog(@"Check initialization. %@", _job);
    
    _job = [AHLaunchJob new];
    _job.Label = lDict[@"Label"];
    _job.ProgramArguments = lDict[@"ProgramArguments"];
    _job.StandardOutPath = lDict[@"StandardOutPath"];
    _job.StandardErrorPath = lDict[@"StandardErrorPath"];
    _job.StartInterval = (NSInteger)lDict[@"StartInterval"];
    _job.RunAtLoad = (isStart > 0) ? YES : NO;
    
    NSError *error = nil;
    if (![[AHLaunchCtl sharedController] add:_job toDomain:kAHGlobalLaunchDaemon error:&error]) {
        NSLog(@"Error Adding Job: %@", error.localizedDescription);
    }
    
    NSString *licenseKey = @"START PATCH Sync";
    reply(error, licenseKey);
}

- (void)stopPatchSyncService:(NSData *)authData startOnBoot:(NSInteger)isStart withReply:(void(^)(NSError * error, NSString * licenseKey))reply
{
    NSDictionary *lDict;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:LAUNCHD_ORIG_PATCH_SYNC])
    {
        lDict = [NSDictionary dictionaryWithContentsOfFile:LAUNCHD_ORIG_PATCH_SYNC];
    } else {
        lDict = @{ @"Label" :  @"gov.llnl.mp.sync",
                     @"ProgramArguments" :  @[ @"/Library/MacPatch/Server/conf/scripts/MPSyncContent.py" ],
                     @"StandardOutPath": @"/Library/MacPatch/Server/Logs/mp_sync_stdout.log",
                     @"StandardErrorPath": @"/Library/MacPatch/Server/Logs/mp_sync_stderr.log",
                     @"StartInterval": @1800,
                     @"RunAtLoad": @NO
                     };
    }
    
    AHLaunchJob *_job = [[AHLaunchJob alloc] init];
    NSLog(@"Check initialization. %@", _job);
    
    _job = [AHLaunchJob new];
    _job.Label = lDict[@"Label"];
    _job.ProgramArguments = lDict[@"ProgramArguments"];
    _job.StandardOutPath = lDict[@"StandardOutPath"];
    _job.StandardErrorPath = lDict[@"StandardErrorPath"];
    _job.StartInterval = (NSInteger)lDict[@"StartInterval"];
    _job.RunAtLoad = (isStart > 0) ? YES : NO;
    
    NSError *error = nil;
    if (![[AHLaunchCtl sharedController] unload:_job.Label inDomain:kAHGlobalLaunchDaemon error:&error]) {
        NSLog(@"Error Removing Job: %@", error.localizedDescription);
    }
    
    NSString *licenseKey = @"STOP SUS Sync";
    reply(error, licenseKey);
}

- (void)readSyncConf:(NSData *)authData withReply:(void(^)(NSError * error, NSDictionary * syncDict))reply
{
    NSError *err = nil;
    NSDictionary *md;
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:CONTENT_SYNC_CONF_FILE]) {
        md = [NSDictionary dictionaryWithContentsOfFile:CONTENT_SYNC_CONF_FILE];
    } else {
        NSMutableDictionary* details = [NSMutableDictionary dictionary];
        [details setValue:[NSString stringWithFormat:@"Error reading fine %@",CONTENT_SYNC_CONF_FILE] forKey:NSLocalizedDescriptionKey];
        err = [NSError errorWithDomain:NSCocoaErrorDomain code:1001 userInfo:details];
    }
    
    reply(err, md);
}

- (void)readLaunchDSyncConf:(NSData *)authData withReply:(void(^)(NSError * error, NSDictionary * syncDict))reply
{
    NSError *err = nil;
    NSDictionary *md;
    NSString *theFile;
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:LAUNCHD_FILE_PATCH_SYNC]) {
        theFile = LAUNCHD_FILE_PATCH_SYNC;
        md = [NSDictionary dictionaryWithContentsOfFile:LAUNCHD_FILE_PATCH_SYNC];
    } else if ([fm fileExistsAtPath:LAUNCHD_ORIG_PATCH_SYNC]) {
        theFile = LAUNCHD_ORIG_PATCH_SYNC;
        md = [NSDictionary dictionaryWithContentsOfFile:LAUNCHD_ORIG_PATCH_SYNC];
    } else {
        NSMutableDictionary* details = [NSMutableDictionary dictionary];
        [details setValue:[NSString stringWithFormat:@"Error reading launchd files."] forKey:NSLocalizedDescriptionKey];
        err = [NSError errorWithDomain:NSCocoaErrorDomain code:1001 userInfo:details];
    }
    
    reply(err, md);
}

- (void)writeSyncConf:(NSData *)authData syncConf:(NSDictionary *)syncDict launchDConf:(NSDictionary *)launchDConf withReply:(void(^)(NSError * error,NSString * licenseKey))reply
{
    NSError *err = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:CONTENT_SYNC_CONF_FILE])
    {
        NSMutableDictionary *scd = [NSMutableDictionary dictionaryWithContentsOfFile:CONTENT_SYNC_CONF_FILE];
        for (NSString *s in syncDict.allKeys) {
            [scd setObject:[syncDict objectForKey:s] forKey:s];
        }
        
        [scd writeToFile:CONTENT_SYNC_CONF_FILE atomically:NO];

    } else {
        [syncDict writeToFile:CONTENT_SYNC_CONF_FILE atomically:NO];
    }
    
    NSString *launchDFile;
    if ([fm fileExistsAtPath:LAUNCHD_FILE_PATCH_SYNC])
    {
        launchDFile = LAUNCHD_FILE_PATCH_SYNC;
    } else {
        launchDFile = LAUNCHD_ORIG_PATCH_SYNC;
    }
    
    if ([fm fileExistsAtPath:launchDFile]) {
        NSMutableDictionary *d = [NSMutableDictionary dictionaryWithContentsOfFile:launchDFile];
        for (NSString *s in launchDConf.allKeys) {
            [d setObject:[launchDConf objectForKey:s] forKey:s];
        }
        
        [d writeToFile:launchDFile atomically:NO];
        //[self setLaunchDFilePermissions:launchDFile];
    } else {
        NSMutableDictionary* details = [NSMutableDictionary dictionary];
        [details setValue:[NSString stringWithFormat:@"Unable to write to file %@",launchDFile] forKey:NSLocalizedDescriptionKey];
        err = [NSError errorWithDomain:NSCocoaErrorDomain code:1003 userInfo:details];
    }
    
    reply(err, @"");
}

#pragma mark Master Rsync Server
// Master Server Config
- (void)startRSyncService:(NSData *)authData startOnBoot:(NSInteger)isStart withReply:(void(^)(NSError * error, NSString * licenseKey))reply
{
    NSDictionary *lDict;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:LAUNCHD_RSYNCD_ORIG])
    {
        lDict = [NSDictionary dictionaryWithContentsOfFile:LAUNCHD_RSYNCD_ORIG];
    } else {
        lDict = @{ @"Label" :  @"org.samba.rsync.mp",
                   @"Program" : @"/usr/bin/rsync",
                   @"ProgramArguments" :  @[ @"/usr/bin/rsync",
                                             @"--daemon",
                                             @"--config=/Library/MacPatch/Server/conf/etc/rsyncd.conf",
                                             @"--no-detach"],
                   @"inetdCompatibility": @{ @"Wait": @NO },
                   @"Sockets": @{ @"Listeners": @{ @"SockServiceName": @"rsync", @"SockType": @"stream"} }
                   };
    }
    
    AHLaunchJob *_job = [[AHLaunchJob alloc] init];
    NSLog(@"Check initialization. %@", _job);
    
    _job = [AHLaunchJob new];
    _job.Label = lDict[@"Label"];
    _job.Program = lDict[@"Program"];
    _job.ProgramArguments = lDict[@"ProgramArguments"];
    _job.inetdCompatibility = lDict[@"inetdCompatibility"];
    _job.Sockets = lDict[@"Sockets"];
    
    NSError *error = nil;
    if (![[AHLaunchCtl sharedController] add:_job toDomain:kAHGlobalLaunchDaemon error:&error]) {
        NSLog(@"Error Adding Job: %@", error.localizedDescription);
    }
    
    NSString *licenseKey = @"START RSyncD";
    reply(error, licenseKey);
}

- (void)stopRSyncService:(NSData *)authData startOnBoot:(NSInteger)isStart withReply:(void(^)(NSError * error, NSString * licenseKey))reply
{
    NSDictionary *lDict;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:LAUNCHD_RSYNCD_ORIG])
    {
        lDict = [NSDictionary dictionaryWithContentsOfFile:LAUNCHD_RSYNCD_ORIG];
    } else {
        lDict = @{ @"Label" :  @"org.samba.rsync.mp",
                   @"Program" : @"/usr/bin/rsync",
                   @"ProgramArguments" :  @[ @"/usr/bin/rsync",
                                             @"--daemon",
                                             @"--config=/Library/MacPatch/Server/conf/etc/rsyncd.conf",
                                             @"--no-detach"],
                   @"inetdCompatibility": @{ @"Wait": @NO },
                   @"Sockets": @{ @"Listeners": @{ @"SockServiceName": @"rsync", @"SockType": @"stream"} }
                   };
    }
    
    AHLaunchJob *_job = [[AHLaunchJob alloc] init];
    NSLog(@"Check initialization. %@", _job);
    
    _job = [AHLaunchJob new];
    _job.Label = lDict[@"Label"];
    _job.Program = lDict[@"Program"];
    _job.ProgramArguments = lDict[@"ProgramArguments"];
    _job.inetdCompatibility = lDict[@"inetdCompatibility"];
    _job.Sockets = lDict[@"Sockets"];
    
    NSError *error = nil;
    if (![[AHLaunchCtl sharedController] unload:_job.Label inDomain:kAHGlobalLaunchDaemon error:&error]) {
        NSLog(@"Error Adding Job: %@", error.localizedDescription);
    }
    
    NSString *licenseKey = @"STOP RSyncD";
    reply(error, licenseKey);

}

- (void)readRsyncConf:(NSData *)authData withReply:(void(^)(NSError * error, NSDictionary * rsyncDict))reply
{
    NSError *err = nil;
    MPRsyncD *r = [[MPRsyncD alloc] init];
    reply(err, [r readContentSettingsForUI]);
}

- (void)writeRsyncConf:(NSData *)authData rsyncConf:(NSDictionary *)rsyncDict launchDConf:(NSDictionary *)launchDConf withReply:(void(^)(NSError * error, NSString * licenseKey))reply
{
    MPRsyncD *r = [[MPRsyncD alloc] init];
    NSError *err = nil;
    
    [r writeChangesForHostsAndConnections:[rsyncDict objectForKey:@"hostsAllow"] hostsDeny:[rsyncDict objectForKey:@"hostsDeny"] connections:[rsyncDict objectForKey:@"maxConnections"]];
    
    
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *launchDFile;
    if ([fm fileExistsAtPath:LAUNCHD_RSYNCD_FILE])
    {
        launchDFile = LAUNCHD_RSYNCD_FILE;
    } else {
        launchDFile = LAUNCHD_RSYNCD_ORIG;
    }
    
    if ([fm fileExistsAtPath:launchDFile]) {
        NSMutableDictionary *d = [NSMutableDictionary dictionaryWithContentsOfFile:launchDFile];
        for (NSString *s in launchDConf.allKeys) {
            [d setObject:[launchDConf objectForKey:s] forKey:s];
        }
        
        [d writeToFile:launchDFile atomically:NO];
    } else {
        NSMutableDictionary* details = [NSMutableDictionary dictionary];
        [details setValue:[NSString stringWithFormat:@"Unable to write to file %@",launchDFile] forKey:NSLocalizedDescriptionKey];
        err = [NSError errorWithDomain:NSCocoaErrorDomain code:1003 userInfo:details];
    }
    
    reply(err, @"");
}

#pragma mark - SiteConfig

- (void)readSiteConf:(NSData *)authData withReply:(void(^)(NSError * error, NSDictionary * siteConfDict))reply
{
    NSError *err = nil;
    NSDictionary *siteConfig = [self readSiteConfig:SITE_CONFIG error:&err];
    if (err) {
        reply(err, nil);
    }
    
    reply(err, siteConfig);
}

#pragma mark - Database
// DataBase
- (void)readDBConf:(NSData *)authData withReply:(void(^)(NSError * error, NSDictionary * dbDict))reply
{
    NSError *err = nil;
    NSDictionary *siteConfig = [self readSiteConfig:SITE_CONFIG error:&err];
    if (err) {
        reply(err, nil);
    }
    
    NSLog(@"%@",siteConfig);
    
    NSDictionary *settings = nil;
    if (![siteConfig objectForKey:@"settings"]) {
        NSMutableDictionary* details = [NSMutableDictionary dictionary];
        [details setValue:[NSString stringWithFormat:@"database object not found in %@",SITE_CONFIG] forKey:NSLocalizedDescriptionKey];
        err = [NSError errorWithDomain:NSCocoaErrorDomain code:1003 userInfo:details];
        reply(err, nil);
    } else {
        settings = [siteConfig objectForKey:@"settings"];
    }
    
    NSDictionary *dbDict = nil;
    if (![settings objectForKey:@"database"]) {
        NSMutableDictionary* details = [NSMutableDictionary dictionary];
        [details setValue:[NSString stringWithFormat:@"database object not found in %@",SITE_CONFIG] forKey:NSLocalizedDescriptionKey];
        err = [NSError errorWithDomain:NSCocoaErrorDomain code:1003 userInfo:details];
    } else {
        dbDict = [settings objectForKey:@"database"];
    }
    
    reply(err, dbDict);
}

- (void)writeDBConf:(NSData *)authData dbConf:(NSDictionary *)dbDict withReply:(void(^)(NSError * error, NSString * licenseKey))reply
{
    NSError *err = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:SITE_CONFIG])
    {
        NSMutableDictionary *scf = [[NSMutableDictionary dictionaryWithDictionary:[self readSiteConfig:SITE_CONFIG error:&err]] mutableCopy];
        if (err) {
            reply(err, @"");
            return;
        }
        // Set Production Data
        NSMutableDictionary *prdDict = [NSMutableDictionary dictionaryWithDictionary:[scf valueForKeyPath:@"settings.database.prod"]];
        for (NSString *k in [[dbDict objectForKey:@"prod"] allKeys])
        {
            [prdDict setObject:[[dbDict objectForKey:@"prod"] objectForKey:k] forKey:k];
        }
        scf[@"settings"][@"database"][@"prod"] = prdDict;
        
        // Set Read Only Data
        NSMutableDictionary *roDict = [NSMutableDictionary dictionaryWithDictionary:[scf valueForKeyPath:@"settings.database.ro"]];
        for (NSString *k in [[dbDict objectForKey:@"ro"] allKeys])
        {
            [roDict setObject:[[dbDict objectForKey:@"ro"] objectForKey:k] forKey:k];
        }
        scf[@"settings"][@"database"][@"ro"] = roDict;
        
        // Write Site Config Back Out
        err = nil;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:scf options:NSJSONWritingPrettyPrinted error:&err];
        
        // Stuping fix for NSJSONSerialization escaping paths
        NSString *jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        jsonStr = [jsonStr stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"];
        jsonData = [jsonStr dataUsingEncoding:NSUTF8StringEncoding];
        
        [jsonData writeToFile:SITE_CONFIG options:0 error:&err];
        if (err) {
            reply(err, @"");
            return;
        }
        
    }
    else
    {
        NSMutableDictionary* details = [NSMutableDictionary dictionary];
        [details setValue:[NSString stringWithFormat:@"[writeDBConf]: file not found %@",SITE_CONFIG] forKey:NSLocalizedDescriptionKey];
        err = [NSError errorWithDomain:NSCocoaErrorDomain code:1003 userInfo:details];
    }
    
    reply(err, @"");
}

#pragma mark - LDAP
// LDAP
- (void)readLDAPConf:(NSData *)authData withReply:(void(^)(NSError * error, NSDictionary * ldapDict))reply
{
    NSError *err = nil;
    NSDictionary *siteConfig = [self readSiteConfig:SITE_CONFIG error:&err];
    if (err) {
        reply(err, nil);
    }
    
    NSDictionary *settings = nil;
    if (![siteConfig objectForKey:@"settings"]) {
        NSMutableDictionary* details = [NSMutableDictionary dictionary];
        [details setValue:[NSString stringWithFormat:@"ldap object not found in %@",SITE_CONFIG] forKey:NSLocalizedDescriptionKey];
        err = [NSError errorWithDomain:NSCocoaErrorDomain code:1003 userInfo:details];
        reply(err, nil);
    } else {
        settings = [siteConfig objectForKey:@"settings"];
    }
    
    NSDictionary *ldapDict = nil;
    if (![settings objectForKey:@"ldap"]) {
        NSMutableDictionary* details = [NSMutableDictionary dictionary];
        [details setValue:[NSString stringWithFormat:@"ldap object not found in %@",SITE_CONFIG] forKey:NSLocalizedDescriptionKey];
        err = [NSError errorWithDomain:NSCocoaErrorDomain code:1003 userInfo:details];
    } else {
        ldapDict = [settings objectForKey:@"ldap"];
    }
    reply(err, ldapDict);
}

- (void)writeLDAPConf:(NSData *)authData ldapConf:(NSDictionary *)ldapDict withReply:(void(^)(NSError * error, NSString * licenseKey))reply
{
    NSError *err = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:SITE_CONFIG])
    {
        NSMutableDictionary *siteConfig = [NSMutableDictionary dictionaryWithDictionary:[self readSiteConfig:SITE_CONFIG error:&err]];
        if (err) {
            reply(err, @"");
            return;
        }
        // Set Ldap Data
        NSMutableDictionary *lDict = [NSMutableDictionary dictionaryWithDictionary:[siteConfig valueForKeyPath:@"settings.ldap"]];
        for (NSString *k in [ldapDict allKeys])
        {
            [lDict setObject:[ldapDict objectForKey:k] forKey:k];
        }
        [[siteConfig objectForKey:@"settings"] setObject:lDict forKey:@"ldap"];
        
        // Write Site Config Back Out
        err = nil;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:siteConfig options:NSJSONWritingPrettyPrinted error:&err];
        [jsonData writeToFile:SITE_CONFIG options:0 error:&err];
        if (err) {
            reply(err, @"");
            return;
        }   
    }
    else
    {
        NSMutableDictionary* details = [NSMutableDictionary dictionary];
        [details setValue:[NSString stringWithFormat:@"[writeLDAPConf]: file not found %@",SITE_CONFIG] forKey:NSLocalizedDescriptionKey];
        err = [NSError errorWithDomain:NSCocoaErrorDomain code:1003 userInfo:details];
    }
    
    reply(err, @"");
}

- (NSDictionary *)readSiteConfig:(NSString *)siteConfigFile error:(NSError **)error
{
    NSDictionary *result = nil;
    NSError *err = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    
    if ([fm fileExistsAtPath:siteConfigFile])
    {
        err = nil;
        NSData *siteConfigData = [NSData dataWithContentsOfFile:siteConfigFile options:NSDataReadingUncached error:&err];
        if (err) {
            if (error != NULL) *error = err;
            return nil;
        }
        err = nil;
        result = [NSJSONSerialization JSONObjectWithData:siteConfigData options:NSJSONReadingMutableContainers error:&err];
        if (err) {
            if (error != NULL) *error = err;
            return nil;
        }
    } else {
        //NSLog(@"File %@ not found.",filePath);
        NSMutableDictionary* details = [NSMutableDictionary dictionary];
        [details setValue:[NSString stringWithFormat:@"File not found %@",siteConfigFile] forKey:NSLocalizedDescriptionKey];
        err = [NSError errorWithDomain:NSCocoaErrorDomain code:1003 userInfo:details];
        if (error != NULL) *error = err;
    }
    
    return result;
}

@end
