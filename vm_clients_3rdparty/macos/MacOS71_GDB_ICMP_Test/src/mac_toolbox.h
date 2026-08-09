/*
 * mac_toolbox.h - Minimal Mac OS Toolbox headers for Mac OS 7.1
 * Compatible with 68k and PowerPC
 */

#ifndef MAC_TOOLBOX_H
#define MAC_TOOLBOX_H

#include <stdint.h>

/* Basic types */
typedef int8_t SInt8;
typedef uint8_t UInt8;
typedef int16_t SInt16;
typedef uint16_t UInt16;
typedef int32_t SInt32;
typedef uint32_t UInt32;
typedef int16_t short;
typedef uint16_t unsigned short;
typedef int32_t long;
typedef uint32_t unsigned long;

/* Boolean */
typedef UInt8 Boolean;
#define true 1
#define false 0

/* OS types */
typedef UInt32 OSType;
typedef SInt32 OSErr;
typedef UInt32 Size;
typedef UInt8 *Ptr;
typedef UInt8 Byte;

/* Point */
typedef struct Point {
    SInt16 v;
    SInt16 h;
} Point;

/* Rect */
typedef struct Rect {
    SInt16 top;
    SInt16 left;
    SInt16 bottom;
    SInt16 right;
} Rect;

/* Event types */
#define mouseDown 1
#define mouseUp 2
#define keyDown 3
#define keyUp 4
#define autoKey 5
#define updateEvt 6
#define diskEvt 7
#define activEvt 8
#define osEvt 15

/* Event modifiers */
#define cmdKey 0x0008
#define shiftKey 0x0020
#define alphaLock 0x0040
#define optionKey 0x0080
#define controlKey 0x0100

/* EventRecord */
typedef struct EventRecord {
    UInt16 what;
    UInt32 message;
    UInt32 when;
    Point where;
    UInt16 modifiers;
} EventRecord;

/* WindowRef */
typedef Ptr WindowRef;

/* GrafPtr */
typedef struct GrafPort {
    Ptr device;
    Rect portRect;
    SInt16 visibleRegion;
    SInt16 clipRegion;
    Ptr bkPat;
    Ptr fillPat;
    Ptr pnLoc;
    Ptr pnSize;
    SInt16 pnMode;
    SInt16 pnPat;
    SInt16 fillColor;
    SInt16 rgbColor;
    SInt16 patStamp;
    SInt16 patXValid;
    SInt16 patYValid;
    SInt16 patHeight;
    SInt16 patWidth;
    SInt16 patData;
} GrafPort, *GrafPtr;

/* MenuRef */
typedef Ptr MenuRef;

/* ControlRef */
typedef Ptr ControlRef;

/* OSErr values */
#define noErr 0
#define memFullErr -108
#define nilResult -32768

/* Memory functions */
extern Ptr NewPtr(Size byteCount);
extern void DisposePtr(Ptr p);

/* QuickDraw functions */
extern void InitGraf(GrafPtr thePort);
extern void InitPort(GrafPtr thePort);
extern void SetPort(WindowRef window);
extern GrafPtr GetPort(void);

/* Window Manager */
extern WindowRef GetNewWindow(SInt16 windowID, Ptr storage, WindowRef behind);
extern void DisposeWindow(WindowRef window);
extern void ShowWindow(WindowRef window);
extern void HideWindow(WindowRef window);
extern void DrawGrowIcon(WindowRef window);

extern void SetRect(Rect *r, SInt16 left, SInt16 top, SInt16 right, SInt16 bottom);

/* Event Manager */
extern Boolean WaitNextEvent(UInt16 eventMask, EventRecord *theEvent, UInt32 sleep, Ptr mouseRgn);

/* Text */
extern void MoveTo(SInt16 h, SInt16 v);
extern void LineTo(SInt16 h, SInt16 v);
extern void DrawString(const unsigned char *text);

/* Dialog */
typedef struct DialogRecord {
    WindowRef window;
    SInt16 items;
    Rect boundsRect;
    GrafPtr port;
    SInt16 visible;
    SInt16 goAwayFlag;
    SInt16 spareFlag;
    SInt16 activeProc;
    SInt16 textH;
    Rect itemsRect;
} DialogRecord, *DialogPtr;

typedef DialogPtr DialogRef;

/* Alert */
#define stopAlert 1
#define noteAlert 2
#define cautionAlert 3

extern void InitDialogs(Ptr theStorage);
extern DialogRef GetNewDialog(SInt16 dialogID, Ptr storage, WindowRef behind);
extern SInt16 ModalDialog(SInt16 dialogPtr, SInt16 *itemHit);
extern void DisposeDialog(DialogRef dialog);

/* Resource Manager */
#define sysResType 0
#define cursResType 1
#define wdrvResType 2
#define menuResType 4
#define windResType 5
#define dlogResType 6
#define alrtResType 7
#define dITLResType 8
#define fontResType 14
#define sndResType 15

typedef SInt16 ResType;
typedef SInt16 ResID;

extern Ptr GetResource(ResType theType, ResID theID);
extern void DetachResource(Ptr r);
extern void ChangedResource(ResType theType, ResID theID);
extern void UpdateResFile(short refNum);

/* Sound */
#define sysBeep 0

extern void SysBeep(SInt16 duration);

/* Mac OS 7.1 specific */
#define gestaltOSAttr 1
#define gestaltMacOS71 0x00000710

/* Network specific */
#define TCPProt 6
#define ICMPProt 1

/* Simple memory allocation */
#ifndef NULL
#define NULL 0
#endif

/* String length */
#define strlen(s) (sizeof(s) - 1)

/* Memory copy */
#define memcpy(d, s, n) do { \
    UInt8 *dd = (UInt8 *)d; \
    UInt8 *ss = (UInt8 *)s; \
    UInt32 nn = (UInt32)n; \
    while (nn--) *dd++ = *ss++; \
} while (0)

/* String comparison */
#define strcmp(a, b) (({ \
    UInt8 *aa = (UInt8 *)a; \
    UInt8 *bb = (UInt8 *)b; \
    while (*aa && *aa == *bb) { aa++; bb++; } \
    *aa - *bb; \
}))

#endif /* MAC_TOOLBOX_H */
