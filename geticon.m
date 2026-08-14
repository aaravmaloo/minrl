//
// geticon.m - generates AppIcon.iconset/*.png for minrl.
//
// Draws the window+Option-badge design used by the menu bar icon, larger,
// on a fully transparent background. Run via `make icon`.
//
// Usage: ./geticon <output-dir>
//

#import <Cocoa/Cocoa.h>
#import <stdio.h>
#import <stdlib.h>

typedef struct {
    const char *name;
    CGFloat px;
} IconSize;

// iconutil expects exactly this set of filenames inside a *.iconset dir.
static const IconSize kSizes[] = {
    {"icon_16x16",      16},
    {"icon_16x16@2x",   32},
    {"icon_32x32",      32},
    {"icon_32x32@2x",   64},
    {"icon_128x128",    128},
    {"icon_128x128@2x", 256},
    {"icon_256x256",    256},
    {"icon_256x256@2x", 512},
    {"icon_512x512",    512},
    {"icon_512x512@2x", 1024},
};

// Renders the icon at `px` pixels on a fully transparent background: a
// centered dark window glyph, and a small yellow circular Option badge
// in the bottom-right, matching the menu bar icon's composition.
static NSImage *RenderIcon(CGFloat px) {
    return [NSImage imageWithSize:NSMakeSize(px, px)
                           flipped:NO
                    drawingHandler:^BOOL(NSRect rect) {
        (void)rect;
        // No background fill; stays fully transparent.

        // Window glyph, centered, dark, heavy weight.
        NSImage *windowSym = [NSImage imageWithSystemSymbolName:@"macwindow"
                                        accessibilityDescription:nil];
        windowSym = [windowSym imageWithSymbolConfiguration:
            [NSImageSymbolConfiguration configurationWithPointSize:px * 0.5
                                                            weight:NSFontWeightSemibold]];
        if (windowSym != nil) {
            NSImage *tinted = [NSImage imageWithSize:windowSym.size
                                              flipped:NO
                                       drawingHandler:^BOOL(NSRect r) {
                [[NSColor colorWithCalibratedWhite:0.95 alpha:1.0] set];
                [windowSym drawInRect:r
                              fromRect:NSZeroRect
                             operation:NSCompositingOperationSourceOver
                              fraction:1.0];
                NSRectFillUsingOperation(r, NSCompositingOperationSourceAtop);
                return YES;
            }];
            NSSize sz = tinted.size;
            NSRect dst = NSMakeRect((px - sz.width) / 2.0,
                                    (px - sz.height) / 2.0 + px * 0.03,
                                    sz.width, sz.height);
            [tinted drawInRect:dst];
        }

        // Option badge, bottom-right corner of the window, same white
        // glyph treatment as the window symbol, no filled circle behind it.
        CGFloat badgeD = px * 0.34;
        NSRect badgeRect = NSMakeRect(px - badgeD - px * 0.06,
                                      px * 0.06,
                                      badgeD, badgeD);
        NSString *opt = @"\u2325"; // ⌥
        NSFont *font = [NSFont boldSystemFontOfSize:badgeD * 0.85];
        NSDictionary *attrs = @{
            NSFontAttributeName : font,
            NSForegroundColorAttributeName : [NSColor colorWithCalibratedWhite:0.95 alpha:1.0],
        };
        NSSize textSize = [opt sizeWithAttributes:attrs];
        NSPoint textOrigin = NSMakePoint(
            NSMidX(badgeRect) - textSize.width / 2.0,
            NSMidY(badgeRect) - textSize.height / 2.0);
        [opt drawAtPoint:textOrigin withAttributes:attrs];

        return YES;
    }];
}

static BOOL WritePNG(NSImage *image, CGFloat px, NSString *path) {
    // Force exact pixel dimensions regardless of the backing scale by
    // rendering into a fresh bitmap rep of the target size.
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL
                       pixelsWide:(NSInteger)px
                       pixelsHigh:(NSInteger)px
                    bitsPerSample:8
                  samplesPerPixel:4
                         hasAlpha:YES
                         isPlanar:NO
                   colorSpaceName:NSCalibratedRGBColorSpace
                      bytesPerRow:0
                     bitsPerPixel:0];
    rep.size = NSMakeSize(px, px);

    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext =
        [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [image drawInRect:NSMakeRect(0, 0, px, px)
             fromRect:NSZeroRect
            operation:NSCompositingOperationCopy
             fraction:1.0];
    [NSGraphicsContext restoreGraphicsState];

    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG
                                    properties:@{}];
    return [png writeToFile:path atomically:YES];
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "usage: %s <output-iconset-dir>\n", argv[0]);
            return 1;
        }
        NSString *outDir = [NSString stringWithUTF8String:argv[1]];
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm createDirectoryAtPath:outDir
        withIntermediateDirectories:YES
                        attributes:nil
                             error:nil];

        for (size_t i = 0; i < sizeof(kSizes) / sizeof(kSizes[0]); i++) {
            NSImage *icon = RenderIcon(kSizes[i].px);
            NSString *path = [outDir stringByAppendingPathComponent:
                [NSString stringWithFormat:@"%s.png", kSizes[i].name]];
            if (!WritePNG(icon, kSizes[i].px, path)) {
                fprintf(stderr, "failed to write %s\n", path.UTF8String);
                return 1;
            }
            printf("wrote %s (%.0fx%.0f)\n", path.UTF8String,
                   kSizes[i].px, kSizes[i].px);
        }
        return 0;
    }
}
