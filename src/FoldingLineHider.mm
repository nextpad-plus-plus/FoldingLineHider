/*
 * FoldingLineHider plugin for Notepad++ macOS
 * Ported from Windows FoldingLineHider by Leonard Chai
 *
 * Features:
 *   - Toggle visibility of folding lines (SC_ELEMENT_FOLD_LINE)
 *   - Collapse / Uncollapse current fold level
 *   - Persists setting to JSON config file
 *
 * License: GPLv2+
 */

#include "NppPluginInterfaceMac.h"
#include "Scintilla.h"
#import <Cocoa/Cocoa.h>
#include <string>

// ── Plugin state ────────────────────────────────────────────────────────

static const char *PLUGIN_NAME = "Folding Line Hider";
static const int NB_FUNC = 4;
static FuncItem funcItem[NB_FUNC];
static NppData nppData;

static int isFoldingLineHidden = 0;

// ── Forward declarations ────────────────────────────────────────────────

static void toggleFoldingLineVisibility();
static void collapseCurrentLevel();
static void uncollapseCurrentLevel();
static void about();

// ── Helpers ─────────────────────────────────────────────────────────────

static NppHandle getCurScintilla()
{
    int which = -1;
    nppData._sendMessage(nppData._nppHandle, NPPM_GETCURRENTSCINTILLA, 0, (intptr_t)&which);
    return (which == 0) ? nppData._scintillaMainHandle : nppData._scintillaSecondHandle;
}

static intptr_t sci(NppHandle h, uint32_t msg, uintptr_t w = 0, intptr_t l = 0)
{
    return nppData._sendMessage(h, msg, w, l);
}

// ── Config file I/O ─────────────────────────────────────────────────────

static std::string configFilePath()
{
    @autoreleasepool {
        // Ask the host for its plugin config directory (creates it if needed).
        // Fall back to ~/Library/Application Support/Nextpad++/plugins/Config if
        // NPPM_GETPLUGINSCONFIGDIR returns empty (it does not on shipped versions).
        char buf[1024] = {};
        nppData._sendMessage(nppData._nppHandle,
                             NPPM_GETPLUGINSCONFIGDIR,
                             (uintptr_t)sizeof(buf),
                             (intptr_t)buf);
        NSString *dir;
        if (buf[0] != '\0') {
            dir = [NSString stringWithUTF8String:buf];
        } else {
            dir = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                       NSUserDomainMask, YES).firstObject
                       stringByAppendingPathComponent:@"Nextpad++/plugins/Config"];
            [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:nil];
        }
        NSString *newPath = [dir stringByAppendingPathComponent:@"FoldingLineHider.json"];

        // One-shot migration from the pre-fix location
        // (~/.nextpad++/FoldingLineHider.json → plugins/Config/FoldingLineHider.json).
        NSString *oldPath = [NSHomeDirectory() stringByAppendingPathComponent:
                             @".nextpad++/FoldingLineHider.json"];
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![newPath isEqualToString:oldPath] &&
            [fm fileExistsAtPath:oldPath] &&
            ![fm fileExistsAtPath:newPath]) {
            [fm moveItemAtPath:oldPath toPath:newPath error:nil];
        }

        return std::string([newPath UTF8String]);
    }
}

// The host's plugin config dir (NPPM_GETPLUGINSCONFIGDIR), for resolving bundled
// resources like the About-dialog logo. Falls back to the macOS app-support base
// (never a hardcoded ~/.nextpad++ dot-folder).
static NSString *configDirForResources()
{
    char buf[1024] = {};
    nppData._sendMessage(nppData._nppHandle, NPPM_GETPLUGINSCONFIGDIR,
                         (uintptr_t)sizeof(buf), (intptr_t)buf);
    if (buf[0] != '\0')
        return [NSString stringWithUTF8String:buf];
    return [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                NSUserDomainMask, YES).firstObject
                stringByAppendingPathComponent:@"Nextpad++/plugins/Config"];
}

static void loadConfig()
{
    @autoreleasepool {
        NSString *path = [NSString stringWithUTF8String:configFilePath().c_str()];
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (!data) {
            isFoldingLineHidden = 1; // default: hidden
            return;
        }
        NSError *err = nil;
        NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
        if (dict && [dict isKindOfClass:[NSDictionary class]]) {
            NSNumber *val = dict[@"FoldingLineHidden"];
            if (val)
                isFoldingLineHidden = [val intValue];
            else
                isFoldingLineHidden = 1;
        } else {
            isFoldingLineHidden = 1;
        }
    }
}

static void saveConfig()
{
    @autoreleasepool {
        NSDictionary *dict = @{ @"FoldingLineHidden": @(isFoldingLineHidden) };
        NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:nil];
        NSString *path = [NSString stringWithUTF8String:configFilePath().c_str()];
        [data writeToFile:path atomically:YES];
    }
}

// ── Set folding style ───────────────────────────────────────────────────
// The green horizontal lines under collapsed folds are SC_ELEMENT_HIDDEN_LINE (81).
// Reset the element to hide (Scintilla skips drawing when unset).
// Restore the green color to show.
static const int kHiddenLineElement = 81;  // SC_ELEMENT_HIDDEN_LINE
static const intptr_t kHiddenLineColor = (intptr_t)0xFF77CC77; // green, matching host default

static void setFoldingStyle(NppHandle h, bool shouldBeHidden)
{
    if (shouldBeHidden) {
        sci(h, SCI_RESETELEMENTCOLOUR, kHiddenLineElement, 0);
    } else {
        sci(h, SCI_SETELEMENTCOLOUR, kHiddenLineElement, kHiddenLineColor);
    }
}

// ── Commands ────────────────────────────────────────────────────────────

static void toggleFoldingLineVisibility()
{
    isFoldingLineHidden = isFoldingLineHidden ? 0 : 1;
    saveConfig();

    nppData._sendMessage(nppData._nppHandle, NPPM_SETMENUITEMCHECK,
                         (uintptr_t)funcItem[0]._cmdID, (intptr_t)isFoldingLineHidden);

    if (nppData._scintillaMainHandle != 0)
        setFoldingStyle(nppData._scintillaMainHandle, isFoldingLineHidden);
    if (nppData._scintillaSecondHandle != 0)
        setFoldingStyle(nppData._scintillaSecondHandle, isFoldingLineHidden);
}

static void collapseCurrentLevel()
{
    NppHandle h = getCurScintilla();
    if (!h) return;
    intptr_t line = sci(h, SCI_LINEFROMPOSITION, (uintptr_t)sci(h, SCI_GETCURRENTPOS));
    intptr_t level = sci(h, SCI_GETFOLDLEVEL, (uintptr_t)line);
    if (level & SC_FOLDLEVELHEADERFLAG) {
        if (sci(h, SCI_GETFOLDEXPANDED, (uintptr_t)line))
            sci(h, SCI_TOGGLEFOLD, (uintptr_t)line);
    } else {
        intptr_t parent = sci(h, SCI_GETFOLDPARENT, (uintptr_t)line);
        if (parent >= 0 && sci(h, SCI_GETFOLDEXPANDED, (uintptr_t)parent))
            sci(h, SCI_TOGGLEFOLD, (uintptr_t)parent);
    }
}

static void uncollapseCurrentLevel()
{
    NppHandle h = getCurScintilla();
    if (!h) return;
    intptr_t line = sci(h, SCI_LINEFROMPOSITION, (uintptr_t)sci(h, SCI_GETCURRENTPOS));
    intptr_t level = sci(h, SCI_GETFOLDLEVEL, (uintptr_t)line);
    if (level & SC_FOLDLEVELHEADERFLAG) {
        if (!sci(h, SCI_GETFOLDEXPANDED, (uintptr_t)line))
            sci(h, SCI_TOGGLEFOLD, (uintptr_t)line);
    } else {
        intptr_t parent = sci(h, SCI_GETFOLDPARENT, (uintptr_t)line);
        if (parent >= 0 && !sci(h, SCI_GETFOLDEXPANDED, (uintptr_t)parent))
            sci(h, SCI_TOGGLEFOLD, (uintptr_t)parent);
    }
}

static void about()
{
    @autoreleasepool {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"FoldingLineHider v1.1";
        alert.informativeText = @"by leonardchai@gmail.com\n\nmacOS port";
        alert.icon = [[NSImage alloc] initWithContentsOfFile:
                      [configDirForResources() stringByAppendingPathComponent:@"logo100px.png"]];
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
    }
}

// ── Plugin exports ──────────────────────────────────────────────────────

extern "C" NPP_EXPORT void setInfo(NppData data)
{
    nppData = data;

    loadConfig();

    strlcpy(funcItem[0]._itemName, "Hide Folding Line (Toggle)", NPP_MENU_ITEM_SIZE);
    funcItem[0]._pFunc = toggleFoldingLineVisibility;
    funcItem[0]._init2Check = (bool)isFoldingLineHidden;
    funcItem[0]._pShKey = nullptr;

    strlcpy(funcItem[1]._itemName, "Collapse Current Level", NPP_MENU_ITEM_SIZE);
    funcItem[1]._pFunc = collapseCurrentLevel;
    funcItem[1]._init2Check = false;
    funcItem[1]._pShKey = nullptr;

    strlcpy(funcItem[2]._itemName, "Uncollapse Current Level", NPP_MENU_ITEM_SIZE);
    funcItem[2]._pFunc = uncollapseCurrentLevel;
    funcItem[2]._init2Check = false;
    funcItem[2]._pShKey = nullptr;

    strlcpy(funcItem[3]._itemName, "About...", NPP_MENU_ITEM_SIZE);
    funcItem[3]._pFunc = about;
    funcItem[3]._init2Check = false;
    funcItem[3]._pShKey = nullptr;

    // Apply initial visibility
    if (isFoldingLineHidden) {
        if (nppData._scintillaMainHandle != 0)
            setFoldingStyle(nppData._scintillaMainHandle, true);
        if (nppData._scintillaSecondHandle != 0)
            setFoldingStyle(nppData._scintillaSecondHandle, true);
    }
}

extern "C" NPP_EXPORT const char *getName()
{
    return PLUGIN_NAME;
}

extern "C" NPP_EXPORT FuncItem *getFuncsArray(int *nbF)
{
    *nbF = NB_FUNC;
    return funcItem;
}

extern "C" NPP_EXPORT void beNotified(SCNotification *notifyCode)
{
    uintptr_t nppHandle = nppData._nppHandle;

    if (notifyCode->nmhdr.hwndFrom == (void *)(uintptr_t)nppHandle) {
        switch (notifyCode->nmhdr.code) {
            case NPPN_READY:
                // Menu is fully built and cmdIDs assigned — set initial checkmark
                nppData._sendMessage(nppData._nppHandle, NPPM_SETMENUITEMCHECK,
                                     (uintptr_t)funcItem[0]._cmdID, (intptr_t)isFoldingLineHidden);
                break;
            case NPPN_BUFFERACTIVATED:
                // Re-apply fold line state when switching tabs (both hide and show)
                {
                    NppHandle h = getCurScintilla();
                    if (h) setFoldingStyle(h, isFoldingLineHidden);
                }
                break;
            case NPPN_SHUTDOWN:
                break;
            default:
                break;
        }
    }
}

extern "C" NPP_EXPORT intptr_t messageProc(uint32_t, uintptr_t, intptr_t)
{
    return 1;
}
