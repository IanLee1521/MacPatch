//
//  ContentSyncVC.m
//  MPServerAdmin
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

#import "ContentSyncVC.h"
#import "MPServerAdmin.h"
#import <ServiceManagement/ServiceManagement.h>
#import "Constants.h"
#import "Common.h"
#import "HelperTool.h"

#define LAUNCHD_MASTER_FILE    @"/Library/LaunchDaemons/gov.llnl.mp.rsync.plist"
#define SERVICE_MASTER         @"org.samba.rsync.mp"
#define SRVS_ON_MASTER         @"Service is running."
#define SRVS_OFF_MASTER        @"Service is not running."

#define LAUNCHD_CLIENT_FILE    @"/Library/LaunchDaemons/gov.llnl.mp.sync.plist"
#define SERVICE_CLIENT         @"gov.llnl.mp.sync"
#define SRVS_ON_CLIENT         @"Service is running."
#define SRVS_OFF_CLIENT        @"Service is not running."

@interface ContentSyncVC () {
    BOOL _textChanged;
    MPServerAdmin *mpsa;
}

- (void)showServiceState;
- (void)readStartonBootValue;
- (void)checkServiceState;
- (void)readContentSyncData;
- (void)writeSyncConfChanges:(NSDictionary *)aConf launchdConf:(NSDictionary *)lConf;

- (void)readRSyncData;

@end

@implementation ContentSyncVC

@synthesize serviceState1 = _serviceState1;
@synthesize serviceState2 = _serviceState2;

- (void)viewDidLoad
{
    [super viewDidLoad];
    mpsa = [MPServerAdmin sharedInstance];
    
    [self checkServiceState];
    
    _textChanged = FALSE;
    _serviceButton1.title = @"Start Service";
    _serviceState1 = -1;
}

- (void)viewDidAppear
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(editingDidEnd:)
                                                 name:NSControlTextDidEndEditingNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(editingDidChange:)
                                                 name:NSControlTextDidChangeNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(textDidChange:)
                                                 name:NSTextDidChangeNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(textDidEndEditing:)
                                                 name:NSTextDidEndEditingNotification
                                               object:nil];
    
    
    [self checkServiceState];
    [self showServiceState];
    [self readStartonBootValue];
    [self readContentSyncData];
    [self readRSyncData];
}

- (void)viewDidDisappear
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)showServiceState
{
    NSArray *jobs = (__bridge NSArray *)SMCopyAllJobDictionaries(kSMDomainSystemLaunchd);
    if (!jobs) {
        return;
    }
    for (NSDictionary *s in jobs)
    {
        if ([[s objectForKey:@"Label"] isEqualToString:SERVICE_CONTENT_SYNC])
        {
            _serviceStatusText1.stringValue = SRVS_ON_CLIENT;
            _serviceState1 = 1;
            _serviceButton1.title = @"Stop Service";
            _serviceStatusImage1.image = [NSImage imageNamed:@"NSStatusAvailable"];
            break;
        } else {
            _serviceStatusText1.stringValue = SRVS_OFF_CLIENT;
            _serviceState1 = 0;
            _serviceButton1.title = @"Start Service";
            _serviceStatusImage1.image = [NSImage imageNamed:@"NSStatusUnavailable"];
        }
    }
    
    for (NSDictionary *s in jobs)
    {
        if ([[s objectForKey:@"Label"] isEqualToString:SERVICE_RSYNCD])
        {
            if (![s objectForKey:@"PID"])
            {
                _serviceStatusText2.stringValue = SRVS_OFF_CLIENT;
                _serviceState2 = 0;
                _serviceButton2.title = @"Start Service";
                _serviceStatusImage2.image = [NSImage imageNamed:@"NSStatusUnavailable"];
            } else {
                _serviceStatusText2.stringValue = SRVS_ON_CLIENT;
                _serviceState2 = 1;
                _serviceButton2.title = @"Stop Service";
                _serviceStatusImage2.image = [NSImage imageNamed:@"NSStatusAvailable"];
            }
            break;
        } else {
            _serviceStatusText2.stringValue = SRVS_OFF_CLIENT;
            _serviceState2 = 0;
            _serviceButton2.title = @"Start Service";
            _serviceStatusImage2.image = [NSImage imageNamed:@"NSStatusUnavailable"];
        }
        
    }
}

- (IBAction)toggleSyncFromMasterService:(id)sender
{
    _serviceButton1.enabled = FALSE;
    NSInteger onOff = 0;
    if ([self.startOnBootCheckBox1 state] == NSOnState) {
        onOff = 1;
    }
    
    [mpsa connectAndExecuteCommandBlock:^(NSError * connectError)
     {
         if (connectError != nil)
         {
             NSLog(@"Error: %@",connectError.localizedDescription);
         }
         else
         {
             // If Service State is Off
             if (_serviceState1 == 0) {
                 [[mpsa.helperToolConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
                     NSLog(@"Error: %@",proxyError.localizedDescription);
                 }] startPatchSyncService:mpsa.authorization startOnBoot:onOff withReply:^(NSError * commandError, NSString * licenseKey) {
                     if (commandError != nil) {
                         NSLog(@"Error: %@",commandError.localizedDescription);
                         _serviceButton1.enabled = TRUE;
                     } else {
                         //NSLog(@"license = %@\n", licenseKey);
                         [NSThread sleepForTimeInterval:5.0];
                         [self showServiceState];
                         _serviceButton1.enabled = TRUE;
                     }
                 }];
             } else {
                 [[mpsa.helperToolConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
                     NSLog(@"Error: %@",proxyError.localizedDescription);
                 }] stopPatchSyncService:mpsa.authorization startOnBoot:onOff withReply:^(NSError * commandError, NSString * licenseKey) {
                     if (commandError != nil) {
                         NSLog(@"Error: %@",commandError.localizedDescription);
                         _serviceButton1.enabled = TRUE;
                     } else {
                         //NSLog(@"license = %@\n", licenseKey);
                         [NSThread sleepForTimeInterval:5.0];
                         [self showServiceState];
                         _serviceButton1.enabled = TRUE;
                     }
                 }];
             }
         }
     }];
    
    [self showServiceState];
}

- (IBAction)toggleMasterServerSyncService:(id)sender
{
    _serviceButton2.enabled = FALSE;
    NSInteger onOff = 0;
    if ([self.startOnBootCheckBox2 state] == NSOnState) {
        onOff = 1;
    }
    
    [mpsa connectAndExecuteCommandBlock:^(NSError * connectError)
     {
         if (connectError != nil)
         {
             NSLog(@"Error: %@",connectError.localizedDescription);
         }
         else
         {
             // If Service State is Off
             if (_serviceState2 == 0) {
                 [[mpsa.helperToolConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
                     NSLog(@"Error: %@",proxyError.localizedDescription);
                 }] startRSyncService:mpsa.authorization startOnBoot:onOff withReply:^(NSError * commandError, NSString * licenseKey) {
                     if (commandError != nil) {
                         NSLog(@"Error: %@",commandError.localizedDescription);
                         _serviceButton2.enabled = TRUE;
                     } else {
                         //NSLog(@"license = %@\n", licenseKey);
                         [NSThread sleepForTimeInterval:5.0];
                         [self showServiceState];
                         _serviceButton2.enabled = TRUE;
                     }
                 }];
             } else {
                 [[mpsa.helperToolConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
                     NSLog(@"Error: %@",proxyError.localizedDescription);
                 }] stopRSyncService:mpsa.authorization startOnBoot:onOff withReply:^(NSError * commandError, NSString * licenseKey) {
                     if (commandError != nil) {
                         NSLog(@"Error: %@",commandError.localizedDescription);
                         _serviceButton2.enabled = TRUE;
                     } else {
                         //NSLog(@"license = %@\n", licenseKey);
                         [NSThread sleepForTimeInterval:5.0];
                         [self showServiceState];
                         _serviceButton2.enabled = TRUE;
                     }
                 }];
             }
         }
     }];
    
    [self showServiceState];
}

- (void)readStartonBootValue
{
    __block NSDictionary *d;
    [mpsa connectAndExecuteCommandBlock:^(NSError * connectError)
     {
         if (connectError != nil)
         {
             NSLog(@"Error: %@",connectError.localizedDescription);
         }
         else
         {
             [[mpsa.helperToolConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
                 NSLog(@"Error: %@",proxyError.localizedDescription);
             }] readLaunchDFile:LAUNCHD_FILE_PATCH_SYNC withReply:^(NSDictionary *dict) {
                 d = [dict copy];
                 if ([d objectForKey:@"RunAtLoad"])
                 {
                     if ([[d objectForKey:@"RunAtLoad"] boolValue]) {
                         [self.startOnBootCheckBox1 setState:NSOnState];
                     } else {
                         [self.startOnBootCheckBox1 setState:NSOffState];
                     }
                 }
             }];
         }
     }];
}

- (void)checkServiceState
{
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:LAUNCHD_FILE_PATCH_SYNC] == NO && [fm fileExistsAtPath:LAUNCHD_ORIG_PATCH_SYNC] == NO) {
        self.serviceConfText.stringValue = @"Could not locate Apache Web Server. Please verify that it's installed.";
        self.serviceConfText.hidden = NO;
        self.serviceConfImage.hidden = NO;
        self.serviceButton1.enabled = NO;
    } else {
        self.serviceConfText.hidden = YES;
        self.serviceConfImage.hidden = YES;
        self.serviceButton1.enabled = YES;
    }
    
    if ([fm fileExistsAtPath:LAUNCHD_RSYNCD_FILE] == NO && [fm fileExistsAtPath:LAUNCHD_RSYNCD_ORIG] == NO) {
        self.serviceConfText.stringValue = @"Could not locate Apache Web Server. Please verify that it's installed.";
        self.serviceConfText.hidden = NO;
        self.serviceConfImage.hidden = NO;
        self.serviceButton2.enabled = NO;
    } else {
        self.serviceConfText.hidden = YES;
        self.serviceConfImage.hidden = YES;
        self.serviceButton2.enabled = YES;
    }
}

- (void)readContentSyncData
{
    [mpsa connectAndExecuteCommandBlock:^(NSError * connectError)
     {
         if (connectError != nil)
         {
             NSLog(@"Error: %@",connectError.localizedDescription);
         }
         else
         {
             [[mpsa.helperToolConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
                 NSLog(@"Error: %@",proxyError.localizedDescription);
             }] readSyncConf:mpsa.authorization withReply:^(NSError * commandError, NSDictionary *syncDict) {
                 if (commandError != nil) {
                     NSLog(@"Error: %@",commandError.localizedDescription);
                 } else {
                     if ([syncDict objectForKey:@"MPServerAddress"]) {
                         self.masterHostName.stringValue = [syncDict objectForKey:@"MPServerAddress"];
                     } else {
                         self.masterHostName.stringValue = @"localhost";
                     }
                 }
             }];
         }
     }];
    
    [mpsa connectAndExecuteCommandBlock:^(NSError * connectError)
     {
         if (connectError != nil)
         {
             NSLog(@"Error: %@",connectError.localizedDescription);
         }
         else
         {
             [[mpsa.helperToolConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
                 NSLog(@"Error: %@",proxyError.localizedDescription);
             }] readLaunchDSyncConf:mpsa.authorization withReply:^(NSError * commandError, NSDictionary *syncDict) {
                 if (commandError != nil) {
                     NSLog(@"Error: %@",commandError.localizedDescription);
                 } else {
                     if ([syncDict objectForKey:@"StartInterval"]) {
                         self.masterSyncInterval.stringValue = [syncDict objectForKey:@"StartInterval"];
                     } else {
                         self.masterSyncInterval.stringValue = @"1800";
                     }
                 }
             }];
         }
     }];
}

- (void)writeSyncConfChanges:(NSDictionary *)aConf launchdConf:(NSDictionary *)lConf
{
    [mpsa connectAndExecuteCommandBlock:^(NSError * connectError)
     {
         if (connectError != nil)
         {
             NSLog(@"Error: %@",connectError.localizedDescription);
         }
         else
         {
             [[mpsa.helperToolConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
                 NSLog(@"Error: %@",proxyError.localizedDescription);
             }] writeSyncConf:mpsa.authorization syncConf:aConf launchDConf:lConf withReply:^(NSError * commandError, NSString *licenseKey) {
                 if (commandError != nil) {
                     NSLog(@"Error: %@",commandError.localizedDescription);
                 } else {
                     //NSLog(@"%@",licenseKey);
                 }
             }];
         }
     }];
}

- (IBAction)toggleSyncPatchesButton:(id)sender
{
    _textChanged = TRUE;
    NSNotification *note = [NSNotification notificationWithName:@"SyncOnLoad" object:nil];
    [self editingDidEnd:note];
}

- (IBAction)toggleMasterSyncButton:(id)sender
{
    _textChanged = TRUE;
    NSNotification *note = [NSNotification notificationWithName:@"MasterSyncOnLoad" object:nil];
    [self editingDidEnd:note];
}

#pragma mark Rsyncd

- (void)readRSyncData
{
    [mpsa connectAndExecuteCommandBlock:^(NSError * connectError)
     {
         if (connectError != nil)
         {
             NSLog(@"Error: %@",connectError.localizedDescription);
         }
         else
         {
             [[mpsa.helperToolConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
                 NSLog(@"Error: %@",proxyError.localizedDescription);
             }] readRsyncConf:mpsa.authorization withReply:^(NSError * commandError, NSDictionary *rsyncDict) {
                 if (commandError != nil) {
                     NSLog(@"Error: %@",commandError.localizedDescription);
                 } else {
                     //NSLog(@"%@",rsyncDict);
                     if ([rsyncDict objectForKey:@"hosts allow"]) {
                         self.hostsAllow.string = [rsyncDict objectForKey:@"hosts allow"];
                     }
                     if ([rsyncDict objectForKey:@"hosts deny"]) {
                         self.hostsDeny.string = [rsyncDict objectForKey:@"hosts deny"];
                     }
                     
                     if ([rsyncDict objectForKey:@"max connections"]) {
                         self.maxConnextions.stringValue = [rsyncDict objectForKey:@"max connections"];
                     }
                 }
                 
                 dispatch_async(dispatch_get_main_queue(),^{[self.view display];});
             }];
         }
     }];
    
    [mpsa connectAndExecuteCommandBlock:^(NSError * connectError)
     {
         if (connectError != nil)
         {
             NSLog(@"Error: %@",connectError.localizedDescription);
         }
         else
         {
             [[mpsa.helperToolConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
                 NSLog(@"Error: %@",proxyError.localizedDescription);
             }] readLaunchDSyncConf:mpsa.authorization withReply:^(NSError * commandError, NSDictionary *syncDict) {
                 if (commandError != nil) {
                     NSLog(@"Error: %@",commandError.localizedDescription);
                 } else {
                     if ([syncDict objectForKey:@"StartInterval"]) {
                         self.masterSyncInterval.stringValue = [syncDict objectForKey:@"StartInterval"];
                     } else {
                         self.masterSyncInterval.stringValue = @"1800";
                     }
                 }
             }];
         }
     }];
}

#pragma mark - Notifications

// somewhere else in the .m file
- (void)editingDidChange:(NSNotification *)notification
{
    _textChanged = TRUE;
}

- (void)editingDidEnd:(NSNotification *)notification
{
    if (_textChanged == TRUE)
    {   
        if (([notification object] == _masterHostName || [notification object] == _masterSyncInterval) || [[notification name] isEqualTo:@"SyncOnLoad"])
        {
            NSDictionary *syncDict = @{@"MPServerAddress": _masterHostName.stringValue};
            BOOL lDEnabled = ([self.startOnBootCheckBox1 state] == NSOnState);
            
            NSLocale *locale = [NSLocale currentLocale];
            NSString *thousandSeparator = [locale objectForKey:NSLocaleGroupingSeparator];
            NSString *_masterSyncIntervalNew = [_masterSyncInterval.stringValue stringByReplacingOccurrencesOfString:thousandSeparator withString:@""];
            
            NSDictionary *launchDDict = @{@"RunAtLoad": [NSNumber numberWithBool:lDEnabled],@"StartInterval": [NSNumber numberWithInt:[_masterSyncIntervalNew intValue]]};
            [self writeSyncConfChanges:syncDict launchdConf:launchDDict];
        }
        
        if (([notification object] == _maxConnextions || [notification object] == _hostsAllow || [notification object] == _hostsDeny) ||
            [[notification name] isEqualTo:@"MasterSyncOnLoad"])
        {
            NSDictionary *rsyncDict = @{@"hostsAllow": _hostsAllow.string, @"hostsDeny": _hostsDeny.string, @"maxConnections": _maxConnextions.stringValue};
            BOOL lDEnabled = ([self.startOnBootCheckBox2 state] == NSOnState);
            NSDictionary *launchDDict = @{@"RunAtLoad": [NSNumber numberWithBool:lDEnabled]};
            
            [mpsa connectAndExecuteCommandBlock:^(NSError * connectError)
             {
                 if (connectError != nil) {
                     NSLog(@"Error: %@",connectError.localizedDescription);
                 } else {
                     [[mpsa.helperToolConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
                         NSLog(@"Error: %@",proxyError.localizedDescription);
                     }] writeRsyncConf:mpsa.authorization rsyncConf:rsyncDict launchDConf:launchDDict withReply:^(NSError * commandError, NSString *licenseKey) {
                         if (commandError != nil) {
                             NSLog(@"Error: %@",commandError.localizedDescription);
                         } else {
                             //NSLog(@"%@",licenseKey);
                         }
                     }];
                 }
             }];
        }
        _textChanged = FALSE;
    }
}

- (void)textDidChange:(NSNotification *)notification
{
    _textChanged = TRUE;
}

- (void)textDidEndEditing:(NSNotification *)notification
{
    if (([notification object] == _maxConnextions || [notification object] == _hostsAllow || [notification object] == _hostsDeny) ||
        [[notification name] isEqualTo:@"MasterSyncOnLoad"])
    {
        NSDictionary *rsyncDict = @{@"hostsAllow": _hostsAllow.string, @"hostsDeny": _hostsDeny.string, @"maxConnections": _maxConnextions.stringValue};
        BOOL lDEnabled = ([self.startOnBootCheckBox2 state] == NSOnState);
        NSDictionary *launchDDict = @{@"RunAtLoad": [NSNumber numberWithBool:lDEnabled]};
        
        [mpsa connectAndExecuteCommandBlock:^(NSError * connectError)
         {
             if (connectError != nil) {
                 NSLog(@"Error: %@",connectError.localizedDescription);
             } else {
                 [[mpsa.helperToolConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
                     NSLog(@"Error: %@",proxyError.localizedDescription);
                 }] writeRsyncConf:mpsa.authorization rsyncConf:rsyncDict launchDConf:launchDDict withReply:^(NSError * commandError, NSString *licenseKey) {
                     if (commandError != nil) {
                         NSLog(@"Error: %@",commandError.localizedDescription);
                     } else {
                         //NSLog(@"%@",licenseKey);
                     }
                 }];
             }
         }];
        
        _textChanged = FALSE;
    }
}

@end
