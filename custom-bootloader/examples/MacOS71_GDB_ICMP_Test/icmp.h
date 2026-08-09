/***************************************************************************
 * MacOS71_GDB_ICMP_Test - ICMP Header
 * 
 * ICMP (Internet Control Message Protocol) functionality for testing
 * network connectivity from within QEMU or real Mac hardware.
 * 
 * This is a simplified ICMP implementation for demonstration purposes.
 * In a real application, you would use the system's networking stack.
 * 
 * Architecture: Motorola 68k (with fallbacks for PPC)
 * Environment: QEMU or Real Mac with MacTCP/OpenTransport
 * 
 * Note: This implementation uses simplified network access that works
 * within the QEMU environment. For real Mac OS, you would need MacTCP
 * or OpenTransport installed.
 ***************************************************************************/

#ifndef __ICMP_H__
#define __ICMP_H__

#include <stdint.h>
#include "debug_utils.h"

/***************************************************************************
 * ICMP Result Codes
 ***************************************************************************/

typedef enum {
    ICMP_SUCCESS        = 0,    /* Ping successful */
    ICMP_TIMEOUT        = -1,   /* Request timed out */
    ICMP_HOST_UNREACH  = -2,   /* Host unreachable */
    ICMP_NETWORK_ERROR = -3,   /* Network error */
    ICMP_RESOLVE_ERROR = -4,   /* Could not resolve hostname */
    ICMP_GENERIC_ERROR = -5,   /* Generic error */
    ICMP_INVALID_ARGUMENT = -6  /* Invalid argument */
} ICMPResult;

/***************************************************************************
 * ICMP Packet Structure (Simplified)
 ***************************************************************************/

typedef struct __attribute__((packed)) {
    uint8_t type;              /* ICMP type (8 = echo request, 0 = echo reply) */
    uint8_t code;              /* ICMP code */
    uint16_t checksum;         /* Checksum */
    uint16_t identifier;       /* Identifier */
    uint16_t sequence;         /* Sequence number */
    /* Data follows */
} ICMPHeader;

/***************************************************************************
 * Function Declarations
 ***************************************************************************/

/*
 * Initialize the ICMP subsystem.
 * 
 * Returns: 1 on success, 0 on failure
 */
int icmp_init(void);

/*
 * Shutdown the ICMP subsystem.
 */
void icmp_shutdown(void);

/*
 * Send an ICMP echo request (ping) to a host.
 * 
 * Parameters:
 *   hostname - Hostname or IP address to ping
 *   timeout_ms - Timeout in milliseconds
 * 
 * Returns: ICMPResult code
 *   ICMP_SUCCESS - Reply received
 *   ICMP_TIMEOUT - No reply within timeout
 *   ICMP_*_ERROR - Various error conditions
 */
ICMPResult icmp_ping(const char *hostname, int timeout_ms);

/*
 * Get a string description of an ICMP result code.
 * 
 * Parameters:
 *   result - ICMPResult code
 * 
 * Returns: String description
 */
const char* icmp_error_string(ICMPResult result);

/*
 * Calculate ICMP checksum.
 * 
 * Parameters:
 *   buffer - Buffer containing ICMP packet
 *   length - Length of buffer in bytes
 * 
 * Returns: Checksum value
 */
uint16_t icmp_checksum(const uint16_t *buffer, uint32_t length);

/***************************************************************************
 * Utility Functions (Optional)
 ***************************************************************************/

/*
 * Check if networking is available.
 * 
 * Returns: 1 if available, 0 otherwise
 */
int icmp_is_network_available(void);

/*
 * Resolve a hostname to an IP address.
 * 
 * Parameters:
 *   hostname - Hostname to resolve
 *   ip_address - Output: resolved IP address in network byte order
 * 
 * Returns: 1 on success, 0 on failure
 */
int icmp_resolve_hostname(const char *hostname, uint32_t *ip_address);

#endif /* __ICMP_H__ */
