#import <UIKit/UIKit.h>
#import "memptrs.h"

#if DEBUG
#define NSLog(args...) NSLog(@"[CGBA] "args)
#else
#define NSLog(args...)
#endif
#define min(a,b) ((a<b)?a:b)

#define GetVRAMSize(memptrs) 0x4000
#define GetVRAMDataPt(memptrs) (memptrs->rambankdata_ - GetVRAMSize(memptrs))
#define GetRAMDataPt(memptrs) memptrs->rambankdata_
#define GetRAMSize(memptrs) (memptrs->wramdata_[0] - GetRAMDataPt(memptrs))
#define GetROMDataPt(memptrs) (memptrs->memchunk_ + 0x4000)
#define GetROMSize(memptrs) (GetVRAMDataPt(memptrs) - GetROMDataPt(memptrs))

static NSSet *expectedMainVCTitlesSet;
static NSSet *expectedGameMenuTitlesSet;
static NSIndexPath *romCellIndexPath = NULL;
static NSIndexPath *saveStateCellIndexPath = NULL;
static __kindof UITableViewController * __weak saveStateViewController;
static NSString *suffix;
static gambatte::MemPtrs *memptrs = NULL;
static BOOL RTCEnabled = NO;
static BOOL shouldEnableRTC = NO;
static unsigned char *GBAPointers[3];

typedef void(^RSTActionSheetSelectionHandler)(UIActionSheet *actionSheet, NSInteger buttonIndex);
typedef void(^RSTAlertViewSelectionHandler)(UIAlertView *alertView, NSInteger buttonIndex);
typedef NS_ENUM(NSInteger, GBASaveStateViewControllerMode)
{
    GBASaveStateViewControllerModeSaving = 0,
    GBASaveStateViewControllerModeLoading = 1
};

@interface RSTFileBrowserViewController : UITableViewController<UITableViewDelegate>
- (NSString *)filepathForIndexPath:(NSIndexPath *)path;
- (void)refreshDirectory;
- (void)setIgnoreDirectoryContentChanges:(BOOL)ignoreDirectoryContentChanges;
@end

@interface GBAROMTableViewController : RSTFileBrowserViewController
@end

@interface GBASaveStateViewController : UITableViewController
- (NSArray<NSArray<NSDictionary *> *> *)saveStateArray;
- (GBASaveStateViewControllerMode)mode;
- (void)dismissSaveStateViewController:(UIBarButtonItem *)unused;
@end

@interface UIView(Private)
- (__kindof UIViewController *)_viewControllerForAncestor;
@end

@interface GBAEmulatorCore : NSObject
+ (instancetype)sharedCore;
- (void)loadStateFromFilepath:(NSString *)path;
@end

static void __CGBA4iOS_corrupt(NSFileHandle *out, long len, long skip) {
	NSData *data;
	for (long i = 0; i < len; i+=skip) {
		unsigned char byte = (unsigned char)arc4random_uniform(255);
		data = [NSData dataWithBytes:&byte length:1];
		[out writeData:data];
		if (skip-1) {
			[out seekToFileOffset:(out.offsetInFile+min(len-i,skip-1))];
		}
	}
}

static void __CGBA4iOS_handle_game_menu_button(UIActionSheet *self, RSTActionSheetSelectionHandler *modifiedHandler) {
	RSTActionSheetSelectionHandler originalHandler = *modifiedHandler;
	NSLog(@"Handling game view controller menu button");
	NSMutableSet *inputSet = [NSMutableSet new];
	for (int i=0; i<self.numberOfButtons; i++) {
		if (i != self.cancelButtonIndex) {
			NSString *title = [self buttonTitleAtIndex:i];
			NSLog(@"New button: %@", title);
			[inputSet addObject:title];
		}
	}
	NSLog(@"Intersecting set: %@", inputSet);
	NSLog(@"With set: %@", expectedGameMenuTitlesSet);
	[inputSet intersectSet:expectedGameMenuTitlesSet];
	NSLog(@"Comparing set counts (%ld and %ld)", (long)inputSet.count, (long)expectedGameMenuTitlesSet.count);
	if (expectedGameMenuTitlesSet.count == inputSet.count) {
		NSInteger newButtonIndex = [self addButtonWithTitle:[(RTCEnabled ? @"Disable" : @"Enable") stringByAppendingString:@" Real-Time Corruption"]];
		*modifiedHandler = ^(UIActionSheet *actionSheet, NSInteger buttonIndex) {
			originalHandler(actionSheet, buttonIndex);
			if (buttonIndex == newButtonIndex) {
				RTCEnabled = !RTCEnabled;
			}
		};
	}
}

static BOOL __CGBA4iOS_corrupt_path(NSString *path, int minSkip, int maxSkip) {
#define return return NO
	FILE *out_c = fopen(path.UTF8String, "r+");
	if (!out_c) return;
	NSFileHandle *out = [[NSFileHandle alloc] initWithFileDescriptor:fileno(out_c) closeOnDealloc:YES];
	if (!out) {
		fclose(out_c);
		return;
	}
	int inset = arc4random_uniform(10000);
	[out seekToEndOfFile];
	long len = out.offsetInFile - inset - 100;
	if (len > 0) {
		[out seekToFileOffset:inset];
		__CGBA4iOS_corrupt(out, len, arc4random_uniform(maxSkip-minSkip)+minSkip);
		NSLog(@"Corruption completed... I think");
	}
	[out closeFile];
#undef return
	return YES;
}

static void __CGBA4iOS_RTC_tick(NSTimer *timer) {
	if (!memptrs && !GBAPointers[0]) return;
	long size = GetVRAMSize(memptrs);
	if (!size) return;
	NSPointerArray *ptArray = [NSPointerArray pointerArrayWithOptions:(NSPointerFunctionsOpaqueMemory | NSPointerFunctionsOpaquePersonality)];
#define _add(pt) [ptArray addPointer:(void *)(pt)]
#define add(pt, size, count) {_add(pt); _add(size); _add(count);}
	if (memptrs) {
		// I'm not sure if I should be corrupting the ROM but the corruptions are better this way so I'll keep it
		add(GetROMDataPt(memptrs), GetROMSize(memptrs), 3);
		add(GetVRAMDataPt(memptrs), GetVRAMSize(memptrs), 5);
		add(GetRAMDataPt(memptrs), GetRAMSize(memptrs), 3);
	}
	if (GBAPointers[0]) {
		// You can never corrupt enough
		add(GBAPointers[0], 0x40000, 0x20);
		add(GBAPointers[1], 0x20000, 0x20);
		add(GBAPointers[2], 0x400, 5);
	}
#undef add
#undef _add
	for (unsigned char ptIndex = 0; ptIndex < ptArray.count; ptIndex+=3) {
		unsigned char *data = (unsigned char *)[ptArray pointerAtIndex:ptIndex];
		long size = (long)[ptArray pointerAtIndex:ptIndex+1];
		long count = (long)[ptArray pointerAtIndex:ptIndex+2];
		if (!data || !size) continue;
		for (long i = 0; i < count; i++) {
			data[arc4random_uniform(size - 1)] = (unsigned char)arc4random_uniform(255);
		}
	}
}

%hook GBAROMTableViewController

- (void)didDetectLongPressGesture:(UILongPressGestureRecognizer *)gestureRecognizer {
	romCellIndexPath = [self.tableView indexPathForCell:(id)[gestureRecognizer view]];
	%orig;
	romCellIndexPath = nil;
}

- (void)presentViewController:(UIAlertController *)vc animated:(BOOL)animated completion:(void(^)(void))completion {
	if ([vc isKindOfClass:[UIAlertController class]]) {
		NSMutableSet *inputSet = [NSMutableSet setWithArray:[vc.actions valueForKeyPath:@"title"]];
		[inputSet intersectSet:expectedMainVCTitlesSet];
		if (inputSet.count == expectedMainVCTitlesSet.count) {
			NSIndexPath *indexPath = romCellIndexPath;
			NSString *filepath = [self filepathForIndexPath:indexPath];
			if (![filepath.pathExtension.lowercaseString isEqualToString:@"zip"]) {
				if (![[filepath stringByDeletingPathExtension] hasSuffix:suffix] && ![filepath.pathExtension.lowercaseString isEqualToString:@"gba"]) {
					[vc addAction:[UIAlertAction
						actionWithTitle:@"Duplicate & Corrupt"
						style:UIAlertActionStyleDefault
						handler:^(id action){
							self.ignoreDirectoryContentChanges = YES;
							NSString *outPath = [NSString stringWithFormat:@"%@/Corrupted %@%@.%@", filepath.stringByDeletingLastPathComponent, filepath.lastPathComponent.stringByDeletingPathExtension, suffix, filepath.pathExtension];
							NSLog(@"Out: %@", outPath);
							NSString *tmpPath = [outPath stringByAppendingPathExtension:@"tmp"];
							[NSFileManager.defaultManager removeItemAtPath:tmpPath error:nil];
							[NSFileManager.defaultManager copyItemAtPath:filepath toPath:tmpPath error:nil];
							__CGBA4iOS_corrupt_path(tmpPath, 100, 1000);
							[NSFileManager.defaultManager
								replaceItemAtURL:[NSURL fileURLWithPath:outPath]
								withItemAtURL:[NSURL fileURLWithPath:tmpPath]
								backupItemName:nil
								options:0
								resultingItemURL:nil
								error:nil
							];
							[NSFileManager.defaultManager
								removeItemAtPath:[outPath.stringByDeletingPathExtension stringByAppendingPathExtension:@"sav"]
								error:nil
							];
							self.ignoreDirectoryContentChanges = NO;
							NSLog(@"Directory should've been refreshed by now");
						}
					]];
				}
				[vc addAction:[UIAlertAction
					actionWithTitle:@"Corrupt in Real Time"
					style:UIAlertActionStyleDefault
					handler:^(id action){
						shouldEnableRTC = YES;
						[self tableView:self.tableView didSelectRowAtIndexPath:indexPath];
					}
				]];
			}
		}
	}
	%orig;
}

- (void)startROM:(id)rom showSameROMAlertIfNeeded:(BOOL)showSameROMAlertIfNeeded {
	RTCEnabled = shouldEnableRTC;
	shouldEnableRTC = NO;
	%orig;
}

%end

%hook RSTFileBrowserViewController

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = %orig;
	if (([self class] == %c(GBAROMTableViewController)) && ![cell.detailTextLabel.text hasPrefix:@"C"] && [cell.textLabel.text hasSuffix:suffix]) {
		cell.textLabel.text = [cell.textLabel.text substringToIndex:cell.textLabel.text.length-suffix.length];
		cell.detailTextLabel.text = [@"C" stringByAppendingString:cell.detailTextLabel.text];
	}
	return cell;
}

%end

%hook UIAlertView

- (void)showWithSelectionHandler:(RSTAlertViewSelectionHandler)selectionHandler {
	if ([self.title isEqualToString:NSLocalizedString(@"Rename Game", @"")] &&
		[[self buttonTitleAtIndex:self.cancelButtonIndex] isEqualToString:NSLocalizedString(@"Cancel", @"")] &&
		[[self buttonTitleAtIndex:self.firstOtherButtonIndex] isEqualToString:NSLocalizedString(@"Rename", @"")])
	{
		UITextField *textField = [self textFieldAtIndex:0];
		if ([textField.text hasSuffix:suffix]) {
			textField.text = [textField.text substringToIndex:textField.text.length-suffix.length];
			RSTAlertViewSelectionHandler modifiedHandler = ^(UIAlertView *alert, NSInteger buttonIndex){
				UITextField *_textField = [alert textFieldAtIndex:0];
				_textField.text = [_textField.text stringByAppendingString:suffix];
				selectionHandler(alert, buttonIndex);
			};
			%orig(modifiedHandler);
			return;
		}
	}
	%orig;
}

%end

%hook UIActionSheet

- (void)showInView:(UIView *)view selectionHandler:(RSTActionSheetSelectionHandler)completionHandler {
	RSTActionSheetSelectionHandler modifiedHandler = completionHandler;
	__CGBA4iOS_handle_game_menu_button(self, &modifiedHandler);
	%orig(view, modifiedHandler);
}

- (void)showFromRect:(CGRect)rect inView:(UIView *)view animated:(BOOL)animated selectionHandler:(RSTActionSheetSelectionHandler)completionHandler {
	NSLog(@"-[%@ %@]", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
	RSTActionSheetSelectionHandler modifiedHandler = completionHandler;
	if ([[self buttonTitleAtIndex:[self firstOtherButtonIndex]] isEqualToString:NSLocalizedString(@"Rename Save State", @"")] &&
		(view == saveStateViewController.tableView) &&
		CGRectEqualToRect(rect, [saveStateViewController.tableView rectForRowAtIndexPath:saveStateCellIndexPath]))
	{
		NSLog(@"Handling save state cell");
		NSIndexPath *indexPath = saveStateCellIndexPath;
		GBASaveStateViewController *vc = [view _viewControllerForAncestor];
		NSString *filePath = vc.saveStateArray[indexPath.section][indexPath.row][@"filepath"];
		NSArray<NSString *> *pathComponents = filePath.pathComponents;
		NSString *docDir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
		if (((pathComponents.count < 2) || !docDir) || ![NSFileManager.defaultManager fileExistsAtPath:[[docDir stringByAppendingPathComponent:pathComponents[pathComponents.count - 2]] stringByAppendingPathExtension:@"gba"]]) {
			NSInteger newButtonIndex = [self addButtonWithTitle:@"Load and Corrupt State"];
			modifiedHandler = ^(UIActionSheet *actionSheet, NSInteger buttonIndex) {
				NSLog(@"Got %ld, expected %ld", (long)buttonIndex, (long)newButtonIndex);
				if (buttonIndex == newButtonIndex) {
					GBASaveStateViewController *vc = [view _viewControllerForAncestor];
					NSString *filePath = vc.saveStateArray[indexPath.section][indexPath.row][@"filepath"];
					NSLog(@"File path: %@", filePath);
					NSLog(@"VC: %@", vc);
					if (!filePath) return;
					NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
					NSLog(@"TMP Path: %@", tmpPath);
					[NSFileManager.defaultManager removeItemAtPath:tmpPath error:nil];
					if (![NSFileManager.defaultManager copyItemAtPath:filePath toPath:tmpPath error:nil]) return;
					if (__CGBA4iOS_corrupt_path(tmpPath, 50, 100)) {
						[[%c(GBAEmulatorCore) sharedCore] loadStateFromFilepath:tmpPath];
					}
					[NSFileManager.defaultManager removeItemAtPath:tmpPath error:nil];
					[vc dismissSaveStateViewController:nil];
				}
				else completionHandler(actionSheet, buttonIndex);
			};
		}
	}
	else {
		__CGBA4iOS_handle_game_menu_button(self, &modifiedHandler);
	}
	%orig(rect, view, animated, modifiedHandler);
}

%end

%hook GBASaveStateViewController

- (void)didDetectLongPressGesture:(UILongPressGestureRecognizer *)gestureRecognizer {
	if (self.mode == GBASaveStateViewControllerModeLoading) {
		saveStateCellIndexPath = [self.tableView indexPathForCell:(id)[gestureRecognizer view]];
		saveStateViewController = self;
	}
	%orig;
	saveStateCellIndexPath = nil;
	saveStateViewController = nil;
}

%end

#pragma mark - Hooks for GBC real time corruption

%hookf(void, "__ZN8gambatte7MemPtrs10setRambankEjj", gambatte::MemPtrs *self, unsigned ramFlags, unsigned rambank) {
	%orig;
	memptrs = self;
}

%hookf(bool, "__ZN8gambatte7MemPtrsD1Ev", gambatte::MemPtrs *self) {
	memptrs = NULL;
	return %orig;
}

%hookf(void, "__ZN9EmuSystem15closeSystem_GBCEv", unsigned char *self) {
	memptrs = NULL;
	%orig;
}

#pragma mark - Hooks for GBA real time corruption

%hookf(bool, "__Z18CPUReadBatteryFileR6GBASysPKc", unsigned char& gba, char const *filename) {
	bool result;
	GBAPointers[0] = NULL;
	if ((result = %orig)) {
		unsigned char *gbaPt = &gba;
		int diff = ((sizeof(void *) == 4) * 2064);
		GBAPointers[0] = gbaPt + 271624 - (diff ? (diff + 8) : 0);
		GBAPointers[1] = gbaPt + 88152 - diff;
		GBAPointers[2] = gbaPt + 219224 - diff;
	}
	return result;
}

%hookf(void, "__ZN9EmuSystem15closeSystem_GBAEv", unsigned char *self) {
	GBAPointers[0] = NULL;
	%orig;
}

%ctor {
	expectedMainVCTitlesSet = [NSSet setWithArray:@[
		NSLocalizedString(@"Cancel", @""),
		NSLocalizedString(@"Rename Game", @""),
		NSLocalizedString(@"Share Game", @"")
	]];
	expectedGameMenuTitlesSet = [NSSet setWithArray:@[
		NSLocalizedString(@"Save State", @""),
		NSLocalizedString(@"Load State", @""),
		NSLocalizedString(@"Cheat Codes", @""),
		NSLocalizedString(@"Sustain Button", @"")
	]];
	GBAPointers[0] = NULL;
	char buffer[5];
	for (unsigned char i=0; i<=3; i++) {
		buffer[i] = i+0x11;
	}
	buffer[4] = 0;
	suffix = @(buffer);
	[NSTimer scheduledTimerWithTimeInterval:1.0
		repeats:YES
		block:^(NSTimer *timer){
			if (RTCEnabled) __CGBA4iOS_RTC_tick(timer);
		}
	];
}