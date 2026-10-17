#import "NativeTextView.h"
@implementation NativeTextView
- (void)keyDown:(NSEvent *)event {
    if (event.keyCode == 36 || event.keyCode == 76) {
        self.returnEvents += 1;
        self.lastReturnModifiers = event.modifierFlags;
        self.receivedReturnWithMarkedText = self.hasMarkedText;
        if (self.sendsOnReturn && !(event.modifierFlags & NSEventModifierFlagShift)) {
            self.lastSubmittedText = self.string;
            self.string = @"";
            [self setSelectedRange:NSMakeRange(0, 0)];
        } else {
            [self insertNewline:nil];
        }
        return;
    }
    [super keyDown:event];
}
- (void)setMarkedText:(id)string selectionRange:(NSRange)selectionRange replacementRange:(NSRange)replacementRange {
    NSString *text = [string isKindOfClass:NSAttributedString.class] ? [string string] : string;
    self.markedLineBreaks += [[text componentsSeparatedByString:@"\n"] count] - 1;
    [super setMarkedText:string selectedRange:selectionRange replacementRange:replacementRange];
}
- (NSString *)stringFromRange:(NSRange)range actualRange:(NSRangePointer)actualRange {
    if (self.hidesSurroundingText) { *actualRange = NSMakeRange(NSNotFound, 0); return nil; }
    *actualRange = range;
    return [self.string substringWithRange:range];
}
@end
