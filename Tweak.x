#import <UIKit/UIKit.h>

#if DEBUG
#define NSLog(args...) NSLog(@"[CGBA] "args)
#else
#define NSLog(args...)
#endif
#define min(a,b) ((a<b)?a:b)

static NSSet *expectedTitlesSet;
static NSIndexPath *cellIndexPath;
static NSString *suffix;
typedef void(^RSTAlertViewSelectionHandler)(UIAlertView *alertView, NSInteger buttonIndex);

@interface RSTFileBrowserViewController : UITableViewController
- (NSString *)filepathForIndexPath:(NSIndexPath *)path;
- (void)refreshDirectory;
- (void)setIgnoreDirectoryContentChanges:(BOOL)ignoreDirectoryContentChanges;
@end

@interface GBAROMTableViewController : RSTFileBrowserViewController
@end

static void __CGBA4iOS_corrupt(NSFileHandle *in, NSFileHandle *out, long len, long skip) {
	NSData *data;
	for (long i = 0; i < len; i+=skip) {
		unsigned char byte = (unsigned char)arc4random_uniform(255);
		data = [NSData dataWithBytes:&byte length:1];
		[out writeData:data];
		[in seekToFileOffset:out.offsetInFile];
		if (skip-1) {
			data = [in readDataOfLength:min(len-i,skip-1)];
			[out writeData:data];
		}
	}
	NSLog(@"Got to end");
}

%hook GBAROMTableViewController

- (void)didDetectLongPressGesture:(UILongPressGestureRecognizer *)gestureRecognizer {
	cellIndexPath = [self.tableView indexPathForCell:(id)[gestureRecognizer view]];
	%orig;
	cellIndexPath = nil;
}

- (void)presentViewController:(UIAlertController *)vc animated:(BOOL)animated completion:(void(^)(void))completion {
	if ([vc isKindOfClass:[UIAlertController class]]) {
		NSMutableSet *inputSet = [NSMutableSet setWithArray:[vc.actions valueForKeyPath:@"title"]];
		[inputSet intersectSet:expectedTitlesSet];
		if (inputSet.count == expectedTitlesSet.count) {
			NSString *filepath = [self filepathForIndexPath:cellIndexPath];
			if (![[filepath stringByDeletingPathExtension] hasSuffix:suffix]) {
				[vc addAction:[UIAlertAction
					actionWithTitle:@"Corrupt Game"
					style:UIAlertActionStyleDefault
					handler:^(id action){
						self.ignoreDirectoryContentChanges = YES;
						FILE *in_c = fopen(filepath.UTF8String, "r");
						if (!in_c) return;
						NSFileHandle *in = [[NSFileHandle alloc] initWithFileDescriptor:fileno(in_c) closeOnDealloc:YES];
						if (!in) {
							fclose(in_c);
							return;
						}
						NSString *outPath = [NSString stringWithFormat:@"%@/Corrupted %@%@.%@", filepath.stringByDeletingLastPathComponent, filepath.lastPathComponent.stringByDeletingPathExtension, suffix, filepath.pathExtension];
						NSLog(@"Out: %@", outPath);
						NSString *tmpPath = [outPath stringByAppendingPathExtension:@"tmp"];
						[NSFileManager.defaultManager removeItemAtPath:tmpPath error:nil];
						[NSFileManager.defaultManager copyItemAtPath:filepath toPath:tmpPath error:nil];
						char *tmpPath_c = malloc(strlen(tmpPath.UTF8String)+1);
						strcpy(tmpPath_c, tmpPath.UTF8String);
						FILE *out_c = fopen(tmpPath_c, "r+");
						free(tmpPath_c);
						if (!out_c) return;
						NSFileHandle *out = [[NSFileHandle alloc] initWithFileDescriptor:fileno(out_c) closeOnDealloc:YES];
						if (!out) {
							fclose(out_c);
							return;
						}
						//BOOL isGBAGame = [filepath.pathExtension.lowercaseString isEqualToString:@"gba"];
						int inset = arc4random_uniform(10000);
						[in seekToEndOfFile];
						long len = in.offsetInFile - inset - 100;
						if (len > 0) {
							[in seekToFileOffset:inset];
							[out seekToFileOffset:inset];
							__CGBA4iOS_corrupt(in, out, len, arc4random_uniform(1000)+100);
							NSLog(@"Corruption completed, supposedly");
						}
						[out closeFile];
						[in closeFile];
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
		}
	}
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

// Not a standard UIAlertView method, this is an extension
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

%ctor {
	expectedTitlesSet = [NSSet setWithArray:@[
		NSLocalizedString(@"Cancel", @""),
		NSLocalizedString(@"Rename Game", @""),
		NSLocalizedString(@"Share Game", @"")
	]];
	char buffer[5];
	for (unsigned char i=0; i<=3; i++) {
		buffer[i] = i+0x11;
	}
	buffer[4] = 0;
	suffix = @(buffer);
}