/*
 * icmp_test.h - ICMP ping test headers for Mac OS 7.1
 */

#ifndef ICMP_TEST_H
#define ICMP_TEST_H

#include "mac_toolbox.h"

/* ICMP types */
#define ICMP_ECHO_REQUEST 8
#define ICMP_ECHO_REPLY 0

/* ICMP structure (simplified for Mac OS) */
typedef struct {
    UInt8 type;
    UInt8 code;
    UInt16 checksum;
    UInt16 identifier;
    UInt16 sequence;
    /* Data follows */
} ICMPHeader;

/* ICMP test result */
typedef struct {
    UInt32 sent_count;
    UInt32 received_count;
    UInt32 min_rtt;      /* Minimum round-trip time in ms */
    UInt32 max_rtt;      /* Maximum round-trip time in ms */
    UInt32 total_rtt;    /* Total round-trip time */
    UInt32 errors;
    UInt32 timeout;     /* Timeout in milliseconds */
} ICMPTestResult;

/* ICMP test configuration */
typedef struct {
    const unsigned char *hostname;
    UInt32 count;        /* Number of pings to send */
    UInt32 size;         /* Packet size */
    UInt32 timeout;      /* Timeout in ms */
    Boolean verbose;     /* Verbose output */
} ICMPTestConfig;

/* Function declarations */
void test_icmp_function(const unsigned char *hostname);
Boolean icmp_ping(const unsigned char *hostname, ICMPTestResult *result);
UInt16 icmp_checksum(const UInt16 *buffer, UInt32 length);
void icmp_init(void);
void icmp_cleanup(void);

/* Mac OS 7.1 networking constants */
#define MAC_TCP_VERSION 1
#define OPEN_TRANSPORT_VERSION 1

/* Error codes */
#define ICMP_ERR_NO_NETWORK -1
#define ICMP_ERR_TIMEOUT -2
#define ICMP_ERR_HOST_NOT_FOUND -3
#define ICMP_ERR_NO_MEMORY -4
#define ICMP_ERR_SOCKET -5

/* Default values */
#define ICMP_DEFAULT_COUNT 4
#define ICMP_DEFAULT_SIZE 64
#define ICMP_DEFAULT_TIMEOUT 1000  /* 1 second */

/* ICMP packet size (including IP header) */
#define ICMP_MIN_SIZE 8
#define ICMP_MAX_SIZE 65535

/* Global ICMP test result */
extern volatile ICMPTestResult gICMPResult;

/* Network status */
extern volatile Boolean gNetworkAvailable;

#endif /* ICMP_TEST_H */
