/*
 * Switch macOS input source without focus loss.
 *
 * Uses `TISSelectInputSource` from Carbon framework to change the input source
 * at the system level, without the UI automation that macism uses (which
 * briefly steals focus from the current window).
 */
#include <ApplicationServices/ApplicationServices.h>
#include <Carbon/Carbon.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

/* TISSelectInputSource is not in public headers but is exported from
 * the Carbon framework binary on all supported macOS versions. */
typedef OSStatus (*TISSelectInputSourceFn)(TISInputSourceRef);

static TISSelectInputSourceFn pTISSelectInputSource = NULL;

/**
 * Load private Carbon APIs not in public headers.
 *
 * Dynamically loads TISSelectInputSource from HIToolbox framework via
 * dlopen/dlsym. Called once at program startup.
 */
static void load_private_apis(void) {
    void *h = dlopen("/System/Library/Frameworks/Carbon.framework"
                     "/Versions/A/Frameworks/HIToolbox.framework"
                     "/Versions/A/HIToolbox",
                     RTLD_LAZY);
    if (h) {
        pTISSelectInputSource =
            (TISSelectInputSourceFn)dlsym(h, "TISSelectInputSource");
    }
}

/**
 * Extract source ID string from input source reference into buffer.
 *
 * @param src Input source reference to query
 * @param buf Buffer to store the source ID string
 * @param bufsize Size of the buffer
 *
 * @return 0 on success, 1 on failure.
 */
static int get_source_id(TISInputSourceRef src, char *buf, size_t bufsize) {
    CFStringRef id =
        (CFStringRef)TISGetInputSourceProperty(src, kTISPropertyInputSourceID);
    if (!id) {
        return 1;
    }
    if (!CFStringGetCString(id, buf, bufsize, kCFStringEncodingUTF8)) {
        return 1;
    }
    return 0;
}

/**
 * Print current input source ID to stdout.
 *
 * @return 0 on success, 1 on failure.
 */
static int cmd_current(void) {
    TISInputSourceRef src = TISCopyCurrentKeyboardInputSource();
    if (!src) {
        fprintf(stderr, "failed to get current input source\n");
        return 1;
    }
    char buf[256];
    int rc = get_source_id(src, buf, sizeof(buf));
    if (rc == 0) {
        puts(buf);
    } else
        fprintf(stderr, "failed to read source ID\n");
    CFRelease(src);
    return rc;
}

/**
 * List all available input sources, marking current with '*'.
 *
 * @return 0 on success, 1 on failure.
 */
static int cmd_list(void) {
    TISInputSourceRef cur = TISCopyCurrentKeyboardInputSource();
    char curid[256] = "";
    if (cur) {
        get_source_id(cur, curid, sizeof(curid));
        CFRelease(cur);
    }

    CFArrayRef all = TISCreateInputSourceList(NULL, false);
    if (!all) {
        fprintf(stderr, "failed to list input sources\n");
        return 1;
    }
    CFIndex n = CFArrayGetCount(all);
    for (CFIndex i = 0; i < n; i++) {
        TISInputSourceRef src =
            (TISInputSourceRef)CFArrayGetValueAtIndex(all, i);
        char buf[256];
        if (get_source_id(src, buf, sizeof(buf)) != 0) {
            continue;
        }
        bool is_cur = curid[0] && strcmp(buf, curid) == 0;
        printf("%s %s\n", is_cur ? "*" : " ", buf);
    }
    CFRelease(all);
    return 0;
}

/**
 * Switch to the specified input source (silent on success).
 *
 * @param target_id Input source ID to switch to
 *
 * @return 0 on success, 1 on failure.
 */
static int cmd_set(const char *target_id) {
    CFStringRef target = CFStringCreateWithCString(
        kCFAllocatorDefault, target_id, kCFStringEncodingUTF8);
    if (!target) {
        return 1;
    }

    TISInputSourceRef cur = TISCopyCurrentKeyboardInputSource();
    if (cur) {
        char buf[256];
        if (get_source_id(cur, buf, sizeof(buf)) == 0 &&
            strcmp(buf, target_id) == 0) {
            CFRelease(cur);
            CFRelease(target);
            return 0;
        }
        CFRelease(cur);
    }

    CFArrayRef all = TISCreateInputSourceList(NULL, false);
    if (!all) {
        CFRelease(target);
        return 1;
    }
    CFIndex n = CFArrayGetCount(all);
    TISInputSourceRef found = NULL;
    for (CFIndex i = 0; i < n; i++) {
        TISInputSourceRef src =
            (TISInputSourceRef)CFArrayGetValueAtIndex(all, i);
        CFStringRef sid = (CFStringRef)TISGetInputSourceProperty(
            src, kTISPropertyInputSourceID);
        if (sid && CFStringCompare(sid, target, 0) == kCFCompareEqualTo) {
            found = src;
            break;
        }
    }

    if (!found) {
        fprintf(stderr, "input source not found: %s\n", target_id);
        fprintf(stderr, "run `macos-im-switch list` to see available "
                        "sources\n");
        CFRelease(all);
        CFRelease(target);
        return 1;
    }

    if (!pTISSelectInputSource) {
        fprintf(stderr, "TISSelectInputSource not available on this system\n");
        CFRelease(all);
        CFRelease(target);
        return 1;
    }

    OSStatus err = pTISSelectInputSource(found);
    CFRelease(all);
    CFRelease(target);

    if (err != 0) {
        fprintf(stderr,
                "failed to select input source: %s (OSStatus "
                "%d)\n",
                target_id, (int)err);
        return 1;
    }
    return 0;
}

/** Entry point: dispatch to current/list/set based on arguments. */
int main(int argc, char **argv) {
    load_private_apis();

    if (argc == 1 || (argc == 2 && strcmp(argv[1], "current") == 0)) {
        return cmd_current();
    }
    if (argc == 2 && strcmp(argv[1], "list") == 0) {
        return cmd_list();
    }
    if (argc == 3 && strcmp(argv[1], "set") == 0) {
        return cmd_set(argv[2]);
    }

    fprintf(stderr, "Usage: macos-im-switch [list|current|set <source_id>]\n");
    return 1;
}
