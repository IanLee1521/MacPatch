//
//  MPClientStatusAppDelegate.m
/*
 Copyright (c) 2013, Lawrence Livermore National Security, LLC.
 Produced at the Lawrence Livermore National Laboratory (cf, DISCLAIMER).
 Written by Charles Heizer <heizer1 at llnl.gov>.
 LLNL-CODE-636469 All rights reserved.
 
 This file is part of MacPatch, a program for installing and patching
 software.
 
 MacPatch is free software; you can redistribute it and/or modify it under
 the terms of the GNU General Public License (as published by the Free
 Software Foundation) version 2, dated June 1991.
 
 MacPatch is distributed in the hope that it will be useful, but WITHOUT ANY
 WARRANTY; without even the IMPLIED WARRANTY OF MERCHANTABILITY or FITNESS
 FOR A PARTICULAR PURPOSE. See the terms and conditions of the GNU General Public
 License for more details.
 
 You should have received a copy of the GNU General Public License along
 with MacPatch; if not, write to the Free Software Foundation, Inc.,
 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
 */

#import "MPClientStatusAppDelegate.h"
#import "MacPatch.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import "MPAppUsage.h"
#import "MPWorkerProtocol.h"
#import "AppLaunchObject.h"
#import "CHMenuViewController.h"
#import "VDKQueue.h"
#import "EventToSend.h"


// Private Methods
@interface MPClientStatusAppDelegate ()

// Helper
- (void)connect;
- (int)connect:(NSError **)err;
- (void)cleanup;
- (void)connectionDown:(NSNotification *)notification;

// Worker Methods
- (void)disableASUSSchedule;

// Watch Patch Status/Needed
- (void)setupWatchedFolder;
@property (nonatomic, strong) NSDate *lastPatchStatusUpdate;

@property (strong, nonatomic) NSCondition *condition;

@end

// GCD Timer, replaces NSTimer code
dispatch_source_t CreateDispatchTimer(double interval, dispatch_queue_t queue, dispatch_block_t block)
{
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    if (timer)
    {
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, interval * NSEC_PER_SEC), interval * NSEC_PER_SEC, (1ull * NSEC_PER_SEC) / 10);
        dispatch_source_set_event_handler(timer, block);
        dispatch_resume(timer);
    }
    return timer;
}


@implementation MPClientStatusAppDelegate
{
    dispatch_source_t _timer;
}

NSString *const kShowPatchesRequiredNotification    = @"kShowPatchesRequiredNotification";
NSString *const kRebootRequiredNotification         = @"kRebootRequiredNotification";
NSString *const kRefreshStatusIconNotification      = @"kRefreshStatusIconNotification";

#pragma mark Properties
@synthesize window;
@synthesize checkInStatusMenuItem;
@synthesize checkPatchStatusMenuItem;
@synthesize selfVersionInfoMenuItem;
@synthesize MPVersionInfoMenuItem;
@synthesize checkAgentAndUpdateMenuItem;

@synthesize openASUS;
@synthesize asusAlertOpen;

// Client Info
@synthesize clientInfoWindow;
@synthesize clientInfoTableView;
@synthesize clientArrayController;

// Patch Info
@synthesize patchCount;
@synthesize patchNeedsReboot;

// About Window
@synthesize aboutWindow;
@synthesize appIcon;
@synthesize appName;
@synthesize appVersion;

// Reboot Window
@synthesize rebootWindow;
@synthesize rebootTitleText;
@synthesize rebootBodyText;

// Client CheckIn Data
@synthesize queue;

#pragma mark UI Events
-(void)awakeFromNib
{
    // Remove all notifications, will get re-added if needed.
    [[NSUserNotificationCenter defaultUserNotificationCenter] removeAllDeliveredNotifications];
    
    // Turn off Scheduled Software Updates
    [self setupWatchedFolder];
    [self setAsusAlertOpen:NO];
    [self disableASUSSchedule];
    
    statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    [statusItem setMenu:statusMenu];
    [statusItem setImage:[NSImage imageNamed:@"mpmenubar_normal.png"]];
    [statusItem setHighlightMode:YES];
    
    // App Version Info
    [selfVersionInfoMenuItem setTitle:[NSString stringWithFormat:@"Status App Version: %@",[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]]];
    NSDictionary *_mpVerDict = [NSDictionary dictionaryWithContentsOfFile:AGENT_VER_PLIST];
    [MPVersionInfoMenuItem setTitle:[NSString stringWithFormat:@"MacPatch Version: %@",[_mpVerDict objectForKey:@"version"]]];
    
    
    [[NSDistributedNotificationCenter defaultCenter] addObserver: self
                                                        selector: @selector(userNotificationReceived:)
                                                            name: kShowPatchesRequiredNotification
                                                          object: nil];
    [[NSDistributedNotificationCenter defaultCenter] addObserver: self
                                                        selector: @selector(userNotificationReceived:)
                                                            name: kRebootRequiredNotification
                                                          object: nil];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Show/hide Quit Menu Item
    NSTimer *t = [NSTimer timerWithTimeInterval:0.1 target:self selector:@selector(updateMenu:) userInfo:statusMenu repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:t forMode:NSEventTrackingRunLoopMode];
    
    //Setup Defaults
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    [prefs registerDefaults:[NSDictionary dictionaryWithContentsOfFile:APP_PREFS_PLIST]];
    
    NSString *_logFile = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/MPClientStatus.log"];
    [MPLog setupLogging:_logFile level:lcl_vDebug];
    
    if ([prefs boolForKey:@"DeBug"] == YES)
    {
        // enable logging for all components up to level Debug
        lcl_configure_by_name("*", lcl_vDebug);
        logit(lcl_vInfo,@"***** MPStatus started -- Debug Enabled *****");
    } else {
        // enable logging for all components up to level Info
        lcl_configure_by_name("*", lcl_vInfo);
        logit(lcl_vInfo,@"***** MPStatus started *****");
    }
    
    // Watch for SoftwareUpdate Launches
    NSNotificationCenter *dc = [[NSWorkspace sharedWorkspace] notificationCenter];
    [dc addObserver:self selector:@selector(notificationReceived:) name:NSWorkspaceWillLaunchApplicationNotification object:[NSWorkspace sharedWorkspace]];
    
    // Setup App monitoring
    mpAppUsage = [[MPAppUsage alloc] init];
    [mpAppUsage cleanDB]; // Removes Entries Where App Version is NULL
    
    [dc addObserver:self selector:@selector(appLaunchNotificationReceived:) name:NSWorkspaceWillLaunchApplicationNotification object:[NSWorkspace sharedWorkspace]];
    
    // Start Last CheckIn Thread, update every 10 min
    [self showLastCheckIn];
    
    // This will monitor for hits, when to update the patch status flags
    [self displayPatchData];
    
    // Run Notification Timer
    [self runMPUserNotificationCenter];
    
    [self setOpenASUS:NO];
}

- (void)applicationWillTerminate:(NSNotification *)note
{
    
}

#pragma mark -
#pragma mark Main

- (void)updateMenu:(NSTimer *)timer
{
    
    static NSMenuItem *menuItem15 = nil;
    static NSMenuItem *menuItem16 = nil;
    static BOOL isShowing = YES;
    
    // Get global modifier key flag, [[NSApp currentEvent] modifierFlags] doesn't update while menus are down
    CGEventRef event = CGEventCreate (NULL);
    CGEventFlags flags = CGEventGetFlags (event);
    BOOL optionKeyIsPressed = (flags & kCGEventFlagMaskAlternate) == kCGEventFlagMaskAlternate;
    CFRelease(event);
    
    NSMenu *menu = [timer userInfo];
    
    if (!menuItem15 && !menuItem16) {
        // View Batch Jobs...
        menuItem15 = [menu itemAtIndex:15];
        menuItem16 = [menu itemAtIndex:16];
    }
    
    if (!isShowing && optionKeyIsPressed) {
        [menu insertItem:menuItem15 atIndex:15];
        [menuItem15 setEnabled:YES];
        [menuItem15 setHidden:NO];
        [menu insertItem:menuItem16 atIndex:16];
        [menuItem16 setEnabled:YES];
        [menuItem16 setHidden:NO];
        isShowing = YES;
    } else if (isShowing && !optionKeyIsPressed) {
        [menu removeItem:menuItem15];
        [menu removeItem:menuItem16];
        isShowing = NO;
    }
    
    [menu update];
}

#pragma mark -
#pragma mark MPWorker
- (void)connect
{
    // Use mach ports for communication, since we're local.
    NSConnection *connection = [NSConnection connectionWithRegisteredName:kMPWorkerPortName host:nil];
    
    [connection setRequestTimeout: 60.0];
    [connection setReplyTimeout: 1800.0]; //30 min to install
    
    @try {
        proxy = [connection rootProxy];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(connectionDown:) name:NSConnectionDidDieNotification object:connection];
        
        [proxy setProtocolForProxy: @protocol(MPWorkerServer)];
        BOOL successful;
        for (int i = 0; i < 3; i++)
        {
            successful = [proxy registerClient:self];
            if (!successful) {
                if (i == 3) {
                    NSAlert *alert = [NSAlert alertWithMessageText:@"Error"
                                                     defaultButton:@"OK" alternateButton:nil
                                                       otherButton:nil
                                         informativeTextWithFormat:@"Unable to connect to helper application. Please try logging out and logging back in to resolve the issue."];
                    
                    [[NSRunningApplication currentApplication] activateWithOptions:NSApplicationActivateIgnoringOtherApps];
                    [alert runModal];
                }
                [self cleanup];
            } else {
                break;
            }
        }
    }
    @catch (NSException *e) {
        logit(lcl_vError,@"Could not connect to MPHelper: %@", e);
        [self cleanup];
    }
}

- (int)connect:(NSError **)err
{
    // Use mach ports for communication, since we're local.
    NSConnection *connection = [NSConnection connectionWithRegisteredName:kMPWorkerPortName host:nil];
    
    [connection setRequestTimeout: 60.0];
    [connection setReplyTimeout: 1800.0]; //30 min to install
    
    @try {
        proxy = [connection rootProxy];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(connectionDown:) name:NSConnectionDidDieNotification object:connection];
        
        [proxy setProtocolForProxy: @protocol(MPWorkerServer)];
        BOOL successful;
        for (int i = 0; i < 3; i++)
        {
            successful = [proxy registerClient:self];
            if (!successful) {
                if (i == 3) {
                    NSAlert *alert = [NSAlert alertWithMessageText:@"Error"
                                                     defaultButton:@"OK" alternateButton:nil
                                                       otherButton:nil
                                         informativeTextWithFormat:@"Unable to connect to helper application. Please try logging out and logging back in to resolve the issue."];
                    
                    [[NSRunningApplication currentApplication] activateWithOptions:NSApplicationActivateIgnoringOtherApps];
                    [alert runModal];
                    
                    NSMutableDictionary *details = [NSMutableDictionary dictionary];
                    [details setValue:@"Unable to connect to helper application. Please try logging out and logging back in to resolve the issue." forKey:NSLocalizedDescriptionKey];
                    if (err != NULL)  *err = [NSError errorWithDomain:@"world" code:1 userInfo:details];
                }
                [self cleanup];
            } else {
                break;
            }
        }
    }
    @catch (NSException *e) {
        logit(lcl_vError,@"Could not connect to MPHelper: %@", e);
        [self cleanup];
    }
    
    return 0;
}

- (void)cleanup
{
    if (proxy)
    {
        NSConnection *connection = [proxy connectionForProxy];
        [connection invalidate];
        proxy = nil;
    }
    
}

- (void)connectionDown:(NSNotification *)notification
{
    logit(lcl_vTrace,@"MPWorker connection down");
    [self cleanup];
}

#pragma mark - Worker Methods

- (void)removeStatusFiles
{
    NSError *error = nil;
    if (!proxy) {
        [self connect:&error];
        if (error) {
            logit(lcl_vError,@"%@",error.localizedDescription);
            goto done;
        }
        if (!proxy) {
            logit(lcl_vError,@"Could not create proxy object.");
            goto done;
        }
    }
    
    @try
    {
        [proxy removeStatusFilesViaHelper];
    }
    @catch (NSException *e) {
        logit(lcl_vError,@"Trying to set the logging level, %@", e);
    }
    
done:
    [self cleanup];
    return;
}

- (void)disableASUSSchedule
{
    NSError *error = nil;
    if (!proxy) {
        [self connect:&error];
        if (error) {
            logit(lcl_vError,@"disableSoftwareUpdateScheduleViaHelper error 1001: %@",[error localizedDescription]);
        }
        if (!proxy) {
            logit(lcl_vError,@"disableSoftwareUpdateScheduleViaHelper error 1002: Unable to get proxy object.");
            goto done;
        }
    }
    
    @try
    {
        logit(lcl_vDebug,@"[proxy run disableSoftwareUpdateScheduleViaHelper]");
        [proxy disableSoftwareUpdateScheduleViaHelper];
    }
    @catch (NSException *e) {
        logit(lcl_vError,@"disableSoftwareUpdateScheduleViaHelper error: %@", e);
    }
    
done:
    [self cleanup];
}

#pragma mark -
#pragma mark Client Info
- (IBAction)getMPClientVersionInfo:(id)sender
{
    [clientArrayController removeObjects:[clientArrayController arrangedObjects]];
    [clientInfoTableView reloadData];
    
    NSDictionary *mpVerDict = [NSDictionary dictionaryWithContentsOfFile:AGENT_VER_PLIST];
    logit(lcl_vDebug,@"mpVerDict: %@", mpVerDict);
    
    NSString *verInfo = [NSString stringWithFormat:@"Version: %@\nBuild: %@\nClient ID: %@",
                         [mpVerDict objectForKey:@"version"],
                         [mpVerDict objectForKey:@"build"],
                         [MPSystemInfo clientUUID]];
    
    [clientInfoTextField setFont:[NSFont fontWithName:@"Lucida Grande" size:11.0]];
    [clientInfoTextField setStringValue:verInfo];
    
    NSMutableArray *data = [[NSMutableArray alloc] init];
    NSMutableDictionary *dict;
    NSDictionary *mpSwuadDict = [NSDictionary dictionaryWithContentsOfFile:AGENT_PREFS_PLIST];
    int i = 0;
    for (i=0;i < [[mpSwuadDict allKeys] count];i++) {
        dict = [[NSMutableDictionary alloc] init];
        [dict setObject:[[mpSwuadDict allKeys] objectAtIndex:i] forKey:@"property"];
        [dict setObject:[[mpSwuadDict allValues] objectAtIndex:i] forKey:@"value"];
        [data addObject:dict];
        dict = nil;
    }
    
    [clientArrayController addObjects:data];
    [clientInfoTableView reloadData];
    [clientInfoTableView deselectAll:self];
    
    
    [clientInfoWindow makeKeyAndOrderFront:sender];
    [clientInfoWindow center];
    [NSApp arrangeInFront:sender];
    [NSApp activateIgnoringOtherApps:YES];
}

- (IBAction)closeClientInfoWindow:(id)sender
{
    [clientInfoWindow close];
}

#pragma mark -
#pragma mark About Window
- (IBAction)showAboutWindow:(id)sender
{
    appName.stringValue = [[NSProcessInfo processInfo] processName];
    appVersion.stringValue = [NSString stringWithFormat:@"Version %@ (%@)",[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"],[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]];
    [appIcon setImage:[NSImage imageNamed:@"NSApplicationIcon"]];
    [aboutWindow makeKeyAndOrderFront:sender];
    [aboutWindow center];
}

#pragma mark -
#pragma mark Reboot Window
- (IBAction)closeRebootWindow:(id)sender {
    [self.rebootWindow close];
}

#pragma mark Checkin
- (IBAction)showCheckinWindow:(id)sender
{
    [NSThread detachNewThreadSelector:@selector(performClientCheckInThread) toTarget:self withObject:nil];
}

- (void)performClientCheckInThread
{
    @autoreleasepool {
        
        BOOL didRun = NO;
        didRun = [self performClientCheckInMethod];
        
        NSAlert *alert = [[NSAlert alloc] init];
        [alert addButtonWithTitle:@"OK"];
        if (didRun == NO) {
            [alert setMessageText:@"Error with check-in"];
            [alert setInformativeText:@"There was a problem checking in with the server. Please review the client status logs for cause."];
            [alert setAlertStyle:NSCriticalAlertStyle];
        } else {
            [alert setMessageText:@"Client check-in"];
            [alert setInformativeText:@"Client check-in was successful."];
            [alert setAlertStyle:NSInformationalAlertStyle];
        }
        
        [alert runModal];
    }
}

// Performs a client checkin
- (BOOL)performClientCheckInMethod
{
    int y = 0;
    
    NSString *_cuuid = [MPSystemInfo clientUUID];
    NSDictionary *osDict = [[NSDictionary alloc] initWithDictionary:[self getOSInfo]];
    
    NSDictionary *consoleUserDict = [MPSystemInfo consoleUserData];
    NSDictionary *hostNameDict = [MPSystemInfo hostAndComputerNames];
    NSDictionary *clientVer = [NSDictionary dictionaryWithContentsOfFile:AGENT_VER_PLIST];
    
    NSMutableDictionary *agentDict = [[NSMutableDictionary alloc] init];
    [agentDict setObject:_cuuid forKey:@"cuuid"];
    [agentDict setObject:[self getHostSerialNumber] forKey:@"serialno" defaultObject:@"NA"];
    [agentDict setObject:[hostNameDict objectForKey:@"localHostName"] forKey:@"hostname" defaultObject:@"localhost"];
    [agentDict setObject:[hostNameDict objectForKey:@"localComputerName"] forKey:@"computername" defaultObject:@"localhost"];
    [agentDict setObject:[consoleUserDict objectForKey:@"consoleUser"] forKey:@"consoleUser" defaultObject:@"NA"];
    [agentDict setObject:[MPSystemInfo getIPAddress] forKey:@"ipaddr" defaultObject:@"127.0.0.1"];
    [agentDict setObject:[MPSystemInfo getMacAddressForInterface:@"en0"] forKey:@"macaddr" defaultObject:@"00:00:00:00:00:00"];
    [agentDict setObject:[osDict objectForKey:@"ProductVersion"] forKey:@"osver" defaultObject:@"10.0.0"];
    [agentDict setObject:[osDict objectForKey:@"ProductName"] forKey:@"ostype" defaultObject:@"Mac OS X"];
    [agentDict setObject:[clientVer objectForKey:@"version"] forKey:@"client_version" defaultObject:@"0"];
    [agentDict setObject:@"false" forKey:@"needsreboot" defaultObject:@"false"];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/private/tmp/.MPAuthRun"]) {
        [agentDict setObject:@"true" forKey:@"needsreboot"];
    }
    
    
    NSError *err = nil;
    BOOL postResult;
    MPWebServices *mpws = [[MPWebServices alloc] init];
    postResult = [mpws postJSONDataForMethod:@"client_checkin_base" data:agentDict error:&err];
    if (err) {
        logit(lcl_vError,@"%@",[err localizedDescription]);
        y++;
    }
    if (postResult) {
        logit(lcl_vInfo,@"Running client base checkin, returned true.");
    } else {
        logit(lcl_vError,@"Running client base checkin, returned false.");
        y++;
    }
    
    // Read Client Plist Info
    
    NSMutableDictionary *mpDefaults = [NSMutableDictionary dictionaryWithContentsOfFile:AGENT_PREFS_PLIST];
    [mpDefaults setObject:_cuuid forKey:@"cuuid"];
    
    err = nil;
    postResult = [mpws postJSONDataForMethod:@"client_checkin_plist" data:mpDefaults error:&err];
    if (err) {
        logit(lcl_vError,@"%@",[err localizedDescription]);
    }
    if (postResult) {
        logit(lcl_vInfo,@"Running client config checkin, returned true.");
    } else {
        logit(lcl_vError,@"Running client config checkin, returned false.");
        y++;
    }
    
    [self showLastCheckInMethod];
    if (y==0) {
        return YES;
    } else {
        return NO;
    }
}

- (NSDictionary *)systemVersionDictionary
{
    NSDictionary *sysVer;
    
    if (floor(NSAppKitVersionNumber) >= NSAppKitVersionNumber10_10) {
        NSOperatingSystemVersion os = [[NSProcessInfo processInfo] operatingSystemVersion];
        sysVer = @{@"major":[NSNumber numberWithInt:(int)os.majorVersion],@"minor":[NSNumber numberWithInt:(int)os.minorVersion],@"revision":[NSNumber numberWithInt:(int)os.patchVersion]};
    } else {
        SInt32 OSmajor, OSminor, OSrevision;
        OSErr err1 = Gestalt(gestaltSystemVersionMajor, &OSmajor);
        OSErr err2 = Gestalt(gestaltSystemVersionMinor, &OSminor);
        OSErr err3 = Gestalt(gestaltSystemVersionBugFix, &OSrevision);
        if (!err1 && !err2 && !err3)
        {
            sysVer = @{@"major":[NSNumber numberWithInt:OSmajor],@"minor":[NSNumber numberWithInt:OSminor],@"revision":[NSNumber numberWithInt:OSrevision]};
        }
    }
    
    return sysVer;
}

- (NSDictionary *)getOSInfo
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *results = nil;
    NSString *clientVerPath = @"/System/Library/CoreServices/SystemVersion.plist";
    NSString *serverVerPath = @"/System/Library/CoreServices/ServerVersion.plist";
    
    if ([fm fileExistsAtPath:serverVerPath] == TRUE) {
        results = [NSDictionary dictionaryWithContentsOfFile:serverVerPath];
    } else {
        if ([fm fileExistsAtPath:clientVerPath] == TRUE) {
            results = [NSDictionary dictionaryWithContentsOfFile:clientVerPath];
        }
    }
    
    return results;
}

- (NSString *)getHostSerialNumber
{
    NSString *result = nil;
    io_registry_entry_t rootEntry = IORegistryEntryFromPath( kIOMasterPortDefault, "IOService:/" );
    CFTypeRef serialAsCFString = NULL;
    serialAsCFString = IORegistryEntryCreateCFProperty( rootEntry,
                                                       CFSTR(kIOPlatformSerialNumberKey),
                                                       kCFAllocatorDefault,
                                                       0);
    
    IOObjectRelease( rootEntry );
    if (serialAsCFString == NULL) {
        result = @"NA";
    } else {
        result = [NSString stringWithFormat:@"%@",(__bridge NSString *)serialAsCFString];
    }
    
    if(serialAsCFString) {
        CFRelease(serialAsCFString);
    }
    return result;
}

#pragma mark Show Last CheckIn Menu
- (void)showLastCheckIn
{
    double secondsToFire = 600.0;
    logit(lcl_vInfo, @"Start Last CheckIn Data Thread");
    logit(lcl_vInfo, @"Run every %f", secondsToFire);
    
    // Show Menu Once, then use timer
    [self performSelectorOnMainThread:@selector(showLastCheckInMethod)
                           withObject:nil
                        waitUntilDone:NO
                                modes:[NSArray arrayWithObject:NSRunLoopCommonModes]];
    
    dispatch_queue_t gcdQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    
    _timer = CreateDispatchTimer(secondsToFire, gcdQueue, ^{
        logit(lcl_vInfo, @"Start, Display Last CheckIn Data in menu.");
        logit(lcl_vDebug, @"Repeats every %f seconds", secondsToFire);
        [self performSelectorOnMainThread:@selector(showLastCheckInMethod)
                               withObject:nil
                            waitUntilDone:NO
                                    modes:[NSArray arrayWithObject:NSRunLoopCommonModes]];
    });
}

- (void)showLastCheckInMethod
{
    @autoreleasepool
    {
        logit(lcl_vInfo, @"Running last agent check in date request.");
        NSError *wsErr = nil;
        MPWebServices *mpws = [[MPWebServices alloc] init];
        NSDictionary *result = [mpws GetLastCheckIn:&wsErr];
        if (wsErr) {
            logit(lcl_vError,@"Web service returned the following error (%d).%@",(int)wsErr.code,wsErr.localizedDescription);
            return;
        }
        
        if ([result objectForKey:@"mdate"]) {
            [checkInStatusMenuItem setTitle:[NSString stringWithFormat:@"Last Checkin: %@",[result objectForKey:@"mdate"]]];
            [statusMenu update];
        }
    }
}

#pragma mark Show Patch Status

- (void)displayPatchData
{
    // Show Menu Once, then use timer
    [self performSelectorOnMainThread:@selector(displayPatchDataMethod)
                           withObject:nil
                        waitUntilDone:NO
                                modes:[NSArray arrayWithObject:NSRunLoopCommonModes]];
    
    dispatch_queue_t gcdQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    double secondsToFire = 180.0;
    
    _timer = CreateDispatchTimer(secondsToFire, gcdQueue, ^{
        logit(lcl_vInfo, @"Start, Display Patch Data Info in menu.");
        logit(lcl_vDebug, @"Repeats every %f seconds", secondsToFire);
        [self performSelectorOnMainThread:@selector(displayPatchDataMethod)
                               withObject:nil
                            waitUntilDone:NO
                                    modes:[NSArray arrayWithObject:NSRunLoopCommonModes]];
    });
}

- (void)displayPatchDataMethod
{
    @autoreleasepool
    {
        logit(lcl_vInfo, @"Running client patch status request.");
        
        self.patchNeedsReboot = NO;
        self.patchCount = 0;
        
        NSArray  *data = [[NSKeyedUnarchiver unarchiveObjectWithFile:PATCHES_NEEDED_PLIST] mutableCopy];
        NSString *subMenuTitle = [NSString stringWithFormat:@"Patches Needed: %d ",(int)[data count]];
        
        // This is for Mac OS X 10.8 support
        // Display notification based on this value
        NSArray *filteredarray = [data filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"(restart == %@)", @"Yes"]];
        if ([filteredarray count] >=1) {
            self.patchNeedsReboot = YES;
        }
        
        // If No Patches ...
        if (!data) {
            [self setPatchCount:0];
            [statusItem setImage:[NSImage imageNamed:@"mpmenubar_normal.png"]];
            [checkPatchStatusMenuItem setTitle:@"Patches Needed: 0"];
            [checkPatchStatusMenuItem setSubmenu:NULL];
            
            if (floor(NSAppKitVersionNumber) >= NSAppKitVersionNumber10_9)
            {
                NSUserDefaults *ud = [[NSUserDefaults alloc] initWithSuiteName:@"mp.cs.note"];
                if ([ud objectForKey:@"reboot"] && [ud objectForKey:@"patch"]) {
                    if ([ud boolForKey:@"reboot"] == YES) {
                        [ud setBool:NO forKey:@"patch"];
                        [ud setBool:NO forKey:@"reboot"];
                        for (NSUserNotification *nox in [[NSUserNotificationCenter defaultUserNotificationCenter] deliveredNotifications]) {
                            if ([nox.title isEqualToString:@"Reboot Patches Required"]) {
                                [[NSUserNotificationCenter defaultUserNotificationCenter] removeDeliveredNotification:nox];
                            }
                        }
                    }
                }
                ud = nil;
            }
            
            [statusMenu update];
            return;
            
        } else if ([data count] <= 0) {
            [self setPatchCount:[data count]];
            [statusItem setImage:[NSImage imageNamed:@"mpmenubar_normal.png"]];
            [checkPatchStatusMenuItem setTitle:@"Patches Needed: 0"];
            [checkPatchStatusMenuItem setSubmenu:NULL];
            [statusMenu update];
            return;

        } else {
            [self setPatchCount:[data count]];
            [statusItem setImage:[NSImage imageNamed:@"mpmenubar_alert2.png"]];
        }
        
        [checkPatchStatusMenuItem setTitle:subMenuTitle];
        NSMenu *subMenu = [[NSMenu alloc] initWithTitle:subMenuTitle];
        [checkPatchStatusMenuItem setSubmenu:subMenu];
        [checkPatchStatusMenuItem setEnabled:YES];
        
        NSMenuItem *newMenuItem;
        
        // Add Header Menu Item
        CHMenuViewController *vcTitle = [[CHMenuViewController alloc] init];
        NSRect f = vcTitle.view.frame;
        f.size.width = 337;
        f.size.height = 26;
        vcTitle.view.frame = f;
        
        [vcTitle.view addSubview:vcTitle.titleView];
        newMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:NULL keyEquivalent:@""];
        [newMenuItem setView:vcTitle.view];
        [subMenu addItem:newMenuItem];
        
        // Add Patches as menu item using views
        CHMenuViewController *vc;
        for (NSDictionary *d in data)
        {
            newMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
            vc = [[CHMenuViewController alloc] init];
            [vc addTitle:[d objectForKey:@"patch"] version:[d objectForKey:@"version"]];
            if ([[[d objectForKey:@"restart"] uppercaseString] isEqualTo:@"TRUE"] || [[[d objectForKey:@"restart"] uppercaseString] isEqualTo:@"YES"])
            {
                vc.ximage = [NSImage imageNamed:@"RestartReq.tif"];
            } else {
                vc.ximage = [NSImage imageNamed:@"empty.tif"];
            }
            [newMenuItem setView:vc.view];
            [subMenu addItem:newMenuItem];
        }
        
        //
        // Add Bottom Menu Item thats says you need to use Self Patch to patch
        //
        CHMenuViewController *vc1 = [[CHMenuViewController alloc] init];
        
        f = vc1.view.frame;
        f.size.width = 337;
        f.size.height = 35;
        vc1.view.frame = f;
        
        [vc1.view addSubview:vc1.altView];
        
        newMenuItem = [[NSMenuItem alloc] initWithTitle:@"Open Self Patch To Patch..." action:NULL keyEquivalent:@""];
        [newMenuItem setView:vc1.view];
        [subMenu addItem:newMenuItem];
        
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:PATCHES_NEEDED_PLIST error:nil];
        if (attrs != nil) {
            [self setLastPatchStatusUpdate:(NSDate*)[attrs objectForKey: NSFileModificationDate]];
        }
        
        // Set User Notification for Reboot
        if (floor(NSAppKitVersionNumber) >= NSAppKitVersionNumber10_9) {
            if ([self patchCount] >= 1) {
                NSUserDefaults *ud = [[NSUserDefaults alloc] initWithSuiteName:@"mp.cs.note"];
                [ud setBool:YES forKey:@"patch"];
                if ([self patchNeedsReboot] == YES) {
                    [ud setBool:YES forKey:@"reboot"];
                } else {
                    [ud setBool:NO forKey:@"reboot"];
                }
                ud = nil;
            }
        }
        
        [statusMenu update];
    }
}

- (IBAction)refreshClientStatus:(id)sender
{
    // Should add scan now action and update without opening self patch
    [self showLastCheckIn];
}

#pragma mark -
#pragma mark Open SelfPatch
- (IBAction)openSelfPatchApplications:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURLs:[NSArray arrayWithObject:[NSURL fileURLWithPath:SELF_PATCH_PATH]]
                    withAppBundleIdentifier:@""
                                    options:NSWorkspaceLaunchDefault
             additionalEventParamDescriptor:nil
                          launchIdentifiers:NULL];
}

#pragma mark -
#pragma mark Kill SoftwareUpdate GUI App
- (void)notificationReceived:(NSNotification *)aNotification
{
    
    if ([[[aNotification userInfo] objectForKey:@"NSApplicationPath"] isEqualToString:ASUS_APP_PATH]) {
        [NSApp activateIgnoringOtherApps:YES];
        if ([self openASUS] == NO)
        {
            [self killApplication:[[aNotification userInfo] objectForKey:@"NSApplicationProcessIdentifier"]];
            
            if (asusAlertOpen == YES)
                return;
            
            NSAlert *alert;
            if ([[NSUserDefaults standardUserDefaults] boolForKey:@"EnableASUS"]) {
                alert = [NSAlert alertWithMessageText:@"Software Update"
                                        defaultButton:@"Open Self Patch"
                                      alternateButton:@"Open Software Update"
                                          otherButton:@"Cancel"
                            informativeTextWithFormat:@"To help ensure patch compatibility for this system, updates are now handled by the \"Self Patch\" application.\n\nWarning: Applying patches using Software Update can screw up your system if you have disk encryption installed."];
            } else {
                alert = [NSAlert alertWithMessageText:@"Software Update"
                                        defaultButton:@"Open Self Patch"
                                      alternateButton:nil
                                          otherButton:@"Cancel"
                            informativeTextWithFormat:@"To help ensure patch compatibility for this system, updates are now handled by the \"Self Patch\" application."];
            }
            
            [self setAsusAlertOpen:YES];
            NSInteger res = [alert runModal];
            
            if (res == NSAlertDefaultReturn) {
                [self openSelfPatchApplications:nil];
                [self setAsusAlertOpen:NO];
            } else if (res == NSAlertAlternateReturn) {
                [self setOpenASUS:YES];
                [self openSoftwareUpdateApplication:nil];
                [self setAsusAlertOpen:NO];
            } else {
                [self setAsusAlertOpen:NO];
            }
            
        } else {
            [self setOpenASUS:NO];
        }
        
    }
    
}

- (void)killApplication:(NSNumber *)aPID
{
    pid_t pid=[aPID intValue];
    kill(pid,SIGKILL);
}

- (void)openSoftwareUpdateApplication:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURLs:[NSArray arrayWithObject:[NSURL fileURLWithPath:ASUS_APP_PATH]]
                    withAppBundleIdentifier:@""
                                    options:NSWorkspaceLaunchDefault
             additionalEventParamDescriptor:nil
                          launchIdentifiers:NULL];
}

#pragma mark - Software Catalog

- (IBAction)openSoftwareCatalogApplications:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURLs:[NSArray arrayWithObject:[NSURL fileURLWithPath:SWDIST_APP_PATH]]
                    withAppBundleIdentifier:@""
                                    options:NSWorkspaceLaunchDefault
             additionalEventParamDescriptor:nil
                          launchIdentifiers:NULL];
}

#pragma mark -
#pragma mark Record App Usage Info
- (void)appLaunchNotificationReceived:(NSNotification *)aNotification
{
    if ([[aNotification userInfo] objectForKey:@"NSApplicationName"]) {
        @try {
            NSBundle *b = [NSBundle bundleWithPath:[[aNotification userInfo] objectForKey:@"NSApplicationPath"]];
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:[aNotification userInfo]];
            [userInfo setObject:[[b infoDictionary] objectForKey:@"CFBundleShortVersionString"] forKey:@"CFBundleShortVersionString"];
            AppLaunchObject *alo = [AppLaunchObject appLaunchObjectWithDictionary:userInfo];
            
            logit(lcl_vDebug,@"Application launched: %@ %@ %@",[alo appName],[alo appPath],[alo appVersion]);
            [mpAppUsage insertLaunchDataForApp:[alo appName] appPath:[alo appPath] appVersion:[alo appVersion]];
        }
        @catch (NSException *exception) {
            logit(lcl_vError,@"%@",exception);
        }
    }
}

#pragma mark -
#pragma mark Softwareupdate
// Softwareupdate Method
- (void)turnOffSoftwareUpdateSchedule
{
    [NSTask launchedTaskWithLaunchPath:ASUS_BIN_PATH arguments:[NSArray arrayWithObjects:@"--schedule", @"off", nil]];
}

- (void)checkAgentStatus:(id)sender
{
    
}

#pragma mark -
#pragma mark Watch Patch Needed File
- (void)setupWatchedFolder
{
    NSString *watchedFolder = [MP_ROOT_CLIENT stringByAppendingPathComponent:@"Data"];
    vdkQueue = [[VDKQueue alloc] init];
    [vdkQueue setDelegate:self];
    [vdkQueue addPath:watchedFolder];
    [vdkQueue setAlwaysPostNotifications:YES];
}

-(void) VDKQueue:(VDKQueue *)queue receivedNotification:(NSString*)note forPath:(NSString*)fpath
{
    if ([note.description isEqualTo:@"VDKQueueFileWrittenToNotification"]) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:PATCHES_NEEDED_PLIST])
        {
            NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:PATCHES_NEEDED_PLIST error:nil];
            
            if (attrs != nil) {
                NSDate *cdate = (NSDate*)[attrs objectForKey: NSFileModificationDate];
                if ([cdate timeIntervalSince1970] > [self.lastPatchStatusUpdate timeIntervalSince1970])
                {
                    [self displayPatchDataMethod];
                }
            }
        }
        else
        {
            [self removeStatusFiles];
        }
    }
}

#pragma mark -
#pragma mark Logout Method

- (void)logoutNow
{
    [self.rebootWindow makeKeyAndOrderFront:nil];
    [self.rebootWindow setLevel:kCGMaximumWindowLevel];
    [self.rebootWindow center];
    [NSApp arrangeInFront:self];
    [NSApp activateIgnoringOtherApps:YES];
}

- (IBAction)logoutAndPatch:(id)sender
{
    // Add .MPAuthRun so that the priv helpr tool runs
    [[NSFileManager defaultManager] createFileAtPath:@"/private/tmp/.MPAuthRun"
                                            contents:[@"Logout" dataUsingEncoding:NSUTF8StringEncoding]
                                          attributes:nil];
    
    if (floor(NSAppKitVersionNumber) >= NSAppKitVersionNumber10_9) {
        NSUserDefaults *ud = [[NSUserDefaults alloc] initWithSuiteName:@"mp.cs.note"];
        [ud setBool:NO forKey:@"patch"];
        [ud setBool:NO forKey:@"reboot"];
        ud = nil;
    }
    
    /* reboot the system using Apple supplied code
     error = SendAppleEventToSystemProcess(kAERestart);
     error = SendAppleEventToSystemProcess(kAELogOut);
     error = SendAppleEventToSystemProcess(kAEReallyLogOut);
     */
    
    OSStatus error = noErr;
#ifdef DEBUG
    error = SendAppleEventToSystemProcess(kAELogOut);
#else
    error = SendAppleEventToSystemProcess(kAEReallyLogOut);
#endif
}

#pragma mark -
#pragma mark NSUserNotificationCenter

- (void)runMPUserNotificationCenter
{
    // Show Menu Once, then use timer
    [self performSelectorOnMainThread:@selector(showMPUserNotificationCenterMethod)
                           withObject:nil
                        waitUntilDone:NO
                                modes:[NSArray arrayWithObject:NSRunLoopCommonModes]];
    
    dispatch_queue_t gcdQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    // 1200.0
    double secondsToFire = 1200.0; // 20 Minutes
    
    _timer = CreateDispatchTimer(secondsToFire, gcdQueue, ^{
        logit(lcl_vInfo, @"Start, Display Patch Data Info in menu.");
        logit(lcl_vDebug, @"Repeats every %f seconds", secondsToFire);
        [self performSelectorOnMainThread:@selector(showMPUserNotificationCenterMethod)
                               withObject:nil
                            waitUntilDone:NO
                                    modes:[NSArray arrayWithObject:NSRunLoopCommonModes]];
    });
}

- (void)showMPUserNotificationCenterMethod
{
    if (floor(NSAppKitVersionNumber) >= NSAppKitVersionNumber10_9)
    {
        // Code for 10.9+ goes here
        NSUserDefaults *ud = [[NSUserDefaults alloc] initWithSuiteName:@"mp.cs.note"];
        if ([ud objectForKey:@"patch"]) {
            if ([ud boolForKey:@"patch"] == YES) {
                if ([ud objectForKey:@"reboot"]) {
                    if ([ud boolForKey:@"reboot"]) {
                        [self postUserNotificationForReboot];
                        return;
                    }
                }
                if (self.patchCount >= 1) {
                    [self postUserNotificationForPatchesWithCount:[@(self.patchCount) stringValue]];
                } else {
                    NSUserNotification *userNote = [[NSUserNotification alloc] init];
                    userNote.title = @"Patches Required";
                    [[NSUserNotificationCenter defaultUserNotificationCenter] removeDeliveredNotification:userNote];
                }
            }
        }
    } else if (floor(NSAppKitVersionNumber) == NSAppKitVersionNumber10_8) {
        @try {
            if (self.patchCount >= 1) {
                if (self.patchNeedsReboot == YES) {
                    [self postUserNotificationForReboot];
                } else {
                    [self postUserNotificationForPatchesWithCount:[@(self.patchCount) stringValue]];
                }
            }
        }
        @catch (NSException *exception) {
            logit(lcl_vError,@"%@",exception);
        }
        
    } else {
        logit(lcl_vInfo,@"floor(NSAppKitVersionNumber): %f",floor(NSAppKitVersionNumber));
        logit(lcl_vInfo,@"NSAppKitVersionNumber10_9:    %d",NSAppKitVersionNumber10_9);
        logit(lcl_vWarning,@"Current OS does not support NSUserNotification");
    }
}

- (void)postUserNotificationForReboot
{
    if (floor(NSAppKitVersionNumber) >= NSAppKitVersionNumber10_8) {
        // Look to see if we have posted already, if we have, no need to do it again
        for(NSUserNotification *deliveredNote in NSUserNotificationCenter.defaultUserNotificationCenter.deliveredNotifications) {
            if([deliveredNote.title isEqualToString:@"Reboot Patches Required"]) {
                return;
            }
        }
    }
    
    NSUserNotification *userNote = [[NSUserNotification alloc] init];
    userNote.title = @"Reboot Patches Required";
    userNote.informativeText = [NSString stringWithFormat:@"This system requires patches that require a reboot."];
    userNote.actionButtonTitle = @"Reboot";
    userNote.hasActionButton = YES;
    userNote.userInfo = @{ @"originalPointer": @((NSUInteger)userNote) };

    if (floor(NSAppKitVersionNumber) >= NSAppKitVersionNumber10_9) {
        [userNote setValue:@YES forKey:@"_showsButtons"];
        //[userNote setValue:@YES forKey:@"_ignoresDoNotDisturb"];
    }
    [[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate:self];
    [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:userNote];
}

- (void)postUserNotificationForPatchesWithCount:(NSString *)aCount
{
    if (floor(NSAppKitVersionNumber) >= NSAppKitVersionNumber10_8) {
        // Look to see if we have posted already, if we have, no need to do it again
        for(NSUserNotification *deliveredNote in NSUserNotificationCenter.defaultUserNotificationCenter.deliveredNotifications) {
            if([deliveredNote.title isEqualToString:@"Patches Required"]) {
                return;
            }
        }
    }
    
    NSUserNotification *userNote = [[NSUserNotification alloc] init];
    userNote.title = @"Patches Required";
    userNote.informativeText = [NSString stringWithFormat:@"This system requires %@ patche(s).",aCount];
    userNote.actionButtonTitle = @"Patch";
    userNote.hasActionButton = YES;
    if (floor(NSAppKitVersionNumber) >= NSAppKitVersionNumber10_9) {
        [userNote setValue:@YES forKey:@"_showsButtons"];
        //[userNote setValue:@YES forKey:@"_ignoresDoNotDisturb"];
    }
    [[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate:self];
    [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:userNote];
}

- (void)userNotificationReceived:(NSNotification *)notification
{
    if ([notification.name isEqualToString: kShowPatchesRequiredNotification])
    {
        NSString *pc = [@(self.patchCount) stringValue];
        [self postUserNotificationForPatchesWithCount:pc];
    }
    else if ([notification.name isEqualToString: kRebootRequiredNotification])
    {
        [self postUserNotificationForReboot];
    }
    else if ([notification.name isEqualToString: kRefreshStatusIconNotification])
    {
        [self displayPatchDataMethod];
    }
    else
    {
        return;
    }
}

- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center shouldPresentNotification:(NSUserNotification *)notification
{
    return YES;
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didActivateNotification:(NSUserNotification *)notification
{
    if (notification.activationType == NSUserNotificationActivationTypeActionButtonClicked)
    {
        if ([notification.actionButtonTitle isEqualToString:@"Patch"]) {
            if (floor(NSAppKitVersionNumber) >= NSAppKitVersionNumber10_9) {
                NSUserDefaults *ud = [[NSUserDefaults alloc] initWithSuiteName:@"mp.cs.note"];
                [ud setBool:NO forKey:@"patch"];
                ud = nil;
            }
            [self openSelfPatchApplications:nil];
        }
        if ([notification.actionButtonTitle isEqualToString:@"Reboot"]) {
            [self logoutNow];
        }
    } else {
        //NSLog(@"Close");
    }
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didDeliverNotification:(NSUserNotification *)notification
{
    if ([notification.actionButtonTitle isEqualToString:@"Patch"]) {
        // Dont show patch info if reboot is required.
        if ([[NSFileManager defaultManager] fileExistsAtPath:@"/private/tmp/.MPAuthRun"]) {
            [[NSUserNotificationCenter defaultUserNotificationCenter] removeDeliveredNotification:notification];
        }
    }
}

@end