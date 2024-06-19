/*
 * Copyright Till Straumann, 2024. Licensed under the EUPL-1.2 or later.
 * You may obtain a copy of the license at
 *   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
 * This notice must not be removed.
 */

/*
 * Test the USB CDCNCM control endpoint design with libusb.
 *
 */

#include <stdio.h>
#include <libusb-1.0/libusb.h>
#include <usb.h>
#include <linux/usb/cdc.h>
#include <getopt.h>
#include <string.h>
#include <time.h>
#include <errno.h>

#define COMM_INTF_NUMBER 0
#define DATA_INTF_NUMBER 1

#define ID_VEND  0x1209
#define ID_PROD  0x0001
#define PHY_IDX  1
#define STRM_LEN 0

#define _STR_(x) # x
#define _STR(x) _STR_(x)

#define VENDOR_CMD_CMDSET_VERSION 0x00
#define VENDOR_CMD_MDIO_RW        0x01
#define VENDOR_CMD_STRM           0x02

struct handle {
	libusb_device_handle *devh;
	unsigned              ifc;
	int                   phy;
};

static void
handle_init(struct handle *h)
{
	h->devh = NULL;
	h->ifc  = -1;
	h->phy  = PHY_IDX;
}

typedef int (*ParseArg)(const char *arg, uint16_t *valp, uint8_t **bufp, size_t *lenp);
typedef int (*PrintRes)(FILE       *f  , uint8_t *bufp, size_t lenp);

struct cmd_map {
	int       cmd;
	uint8_t   req;
	uint8_t   ep;
    int       val;
	ParseArg  prs;
	PrintRes  prp;
};

static int scanMacAddr(const char *arg, uint16_t *valp, uint8_t **bufp, size_t *lenp)
{
int i,ch;
uint8_t v;
int     mymem = (0 == (*bufp));

	if ( mymem ) {
		if ( ! (*bufp = calloc(1,6)) ) {
			fprintf(stderr, "No Memory\n");
			return -1;
		}
	} else {
		memset( *bufp, 0, 6 );
	}

	/* if arg is NULL we just alloc a buffer for readback */
	if ( arg ) {

		for (i = 0; i<12; i++) {
			ch = arg[i];
			if ( ch >= '0' && ch <= '9' ) {
				v = ch - '0';
			} else if ( ch >= 'A' && ch <= 'F' ) {
				v = ch - 'A' + 10;
			} else if ( ch >= 'a' && ch <= 'f' ) {
				v = ch - 'a' + 10;
			} else {
				fprintf(stderr, "Missing hex digit (12 expected)\n");
				goto bail;
			}
			(*bufp)[i/2] |= v << ( i&1 ? 0 : 4 );
		}

	}

	if ( lenp ) {
		*lenp = 6;
	}
	return 0;

bail:
	if ( mymem ) {
		free( *bufp );
		*bufp = 0;
	}
	if ( lenp ) {
		*lenp = 0;
	}
	return -1;
}

static int printMacAddr(FILE *f, uint8_t *buf, size_t len)
{
	if ( len < 6 ) {
		fprintf(stderr, "Unable to print mac address -- response too short!\n");
		return -1;
	}
	while ( len-- > 0 ) {
		fprintf(f, "%02X", *buf);
		buf++;
	}
	fprintf(f, "\n");
	return 0;
}

static int scanBytes(const char *arg, uint16_t *valp, uint8_t **bufp, size_t *lenp)
{
int ncom = 0;
const char *p;
char       *e;
unsigned long v;
size_t        l;
uint8_t      *b = 0;
int          st = -1;

	if ( ! arg || ! *arg ) {
		*bufp = 0;
		*lenp = 0;
		return 0;
	}

	for ( p = arg; (p=strchr(p, ',')); p++ ) {
		ncom++;
	}
	l     = ncom + 1;
	if ( ! (b = malloc( l ) ) ) {
		return -1;
	}
	p     = arg;
    ncom  = 0;
	do {
		v = strtoul( p, &e, 0 );
		if ( e == p ) {
			fprintf(stderr, "unable to scan number.\n");
			goto bail;		
		}
		if ( *e == ',' || *e == '\0' ) {
			if ( ncom < l ) {
				b[ncom] = v;
				ncom++;
			} else {
				fprintf(stderr, "unable to scan arg; unexpected number of values.\n");
				goto bail;		
			}
		} else {
			fprintf(stderr, "unable to scan arg; unexpected separator (not ',')\n");
			goto bail;		
		}
		p = e + 1;
	} while ( *e != '\0' );

	*bufp = b;
	*lenp = l;
	b     = 0;
	st    = 0;
		
bail:
	free( b );
	return st;
}

static int scanMC(const char *arg, uint16_t *valp, uint8_t **bufp, size_t *lenp)
{
	int         ncom, nadr, i;
	const char *p;
	uint8_t    *b  = 0;
    uint8_t     l  = 0;
	int         rv = -1;
	uint8_t    *m;

	if ( !arg || ! *arg ) {
		/* empty list */
		return 0;
	}

	ncom = 0;
	for ( p = arg; (p = strchr(p, ',')); p++ ) {
		ncom++;
	}
	nadr = ncom + 1;

	l    = 6*nadr;
	if ( ! (b = malloc( l ) ) ) {
		fprintf(stderr, "No Memory\n");
		goto bail;
	}

	for ( i = 0, p = arg, m = b; i < nadr; i++, m += 6 ) {
		if ( 0 != i ) {
			if ( ',' != *p ) {
				fprintf(stderr, "Error: comma expected\n");
				goto bail;
			}
			p++;
		}
		if ( scanMacAddr( p, valp /* dummy */, &m, 0 ) ) {
			fprintf(stderr, "Invalid MAC address\n");
			goto bail;
		}
		p += 12;
	}
	
	*valp = nadr;

    *bufp = b;
    *lenp = l;

{ int i;
	printf("scnMC val 0x%04x, buf %p, len %d\n", *valp, *bufp, *lenp);
for ( i = 0; i < *lenp; i++ ) {
printf("%02X,", (*bufp)[i]);
}
printf("\n");
}
    b     = 0;
    rv    = 0;

bail:
	free( b );
	return rv;
}

static int scanVal(const char *arg, uint16_t *valp, uint8_t **bufp, size_t *lenp)
{
	int got = scanBytes(arg, valp, bufp, lenp);
	if ( got ) {
		return got;
	}
	if ( *lenp < 1 ) {
		return -1;
	}
	*valp = (*bufp)[0];
	free( *bufp );
	*lenp = 0;
	*bufp = 0;
	return 0;
}

static struct cmd_map cmdList[] = {
	{ cmd: 'M', req: USB_CDC_SET_ETHERNET_MULTICAST_FILTERS, ep : LIBUSB_ENDPOINT_OUT, val: 0, prs: scanMC     , prp:            0 },
	{ cmd: 'f', req: USB_CDC_SET_ETHERNET_PACKET_FILTER,     ep : LIBUSB_ENDPOINT_OUT, val: 0, prs: scanVal    , prp:            0 },
	{ cmd: 'S', req: USB_CDC_SET_NET_ADDRESS,                ep : LIBUSB_ENDPOINT_OUT, val: 0, prs: scanMacAddr, prp:            0 },
	{ cmd: 'G', req: USB_CDC_GET_NET_ADDRESS,                ep : LIBUSB_ENDPOINT_IN , val: 0, prs: scanMacAddr, prp: printMacAddr },

};

static int
clazz_cmd(struct handle *h, FILE *f, int cmdCod, const char *arg)
{
	int i;
	uint8_t *bufp  = 0;
	size_t   bufsz = 0;
	uint16_t val   = 0;
	int st = -1;

	for ( i = 0; i < sizeof(cmdList)/sizeof(cmdList[0]); i++ ) {
		if ( cmdList[i].cmd == cmdCod ) {
			val = cmdList[i].val;

			if ( cmdList[i].prs ) {
				if ( cmdList[i].ep == LIBUSB_ENDPOINT_IN ) {
					/* indicate that they should just alloc space */
					arg = 0;
				}
				st = cmdList[i].prs( arg, &val, &bufp, &bufsz );
				if ( st ) {
					fprintf(stderr, "Unable to parse argument to -%c (%s)\n", cmdCod, arg);
					break;
				}
			}
    
			st = libusb_control_transfer(
				h->devh,
				( cmdList[i].ep | LIBUSB_REQUEST_TYPE_CLASS | LIBUSB_RECIPIENT_INTERFACE ),
		        cmdList[i].req,
				val,
				h->ifc,
				bufp,
				bufsz,
				1000
			);

			if ( cmdList[i].prp ) {
				cmdList[i].prp( f, bufp, bufsz );
			}
			break;
		}
	}
	free( bufp );
	return st;
}

/*
#define USB_CDC_SET_ETHERNET_MULTICAST_FILTERS	0x40
#define USB_CDC_SET_ETHERNET_PM_PATTERN_FILTER	0x41
#define USB_CDC_GET_ETHERNET_PM_PATTERN_FILTER	0x42
#define USB_CDC_SET_ETHERNET_PACKET_FILTER	0x43
#define USB_CDC_GET_ETHERNET_STATISTIC		0x44
#define USB_CDC_GET_NTB_PARAMETERS		0x80
#define USB_CDC_GET_NET_ADDRESS			0x81
#define USB_CDC_SET_NET_ADDRESS			0x82
#define USB_CDC_GET_NTB_FORMAT			0x83
#define USB_CDC_SET_NTB_FORMAT			0x84
#define USB_CDC_GET_NTB_INPUT_SIZE		0x85
#define USB_CDC_SET_NTB_INPUT_SIZE		0x86
#define USB_CDC_GET_MAX_DATAGRAM_SIZE		0x87
#define USB_CDC_SET_MAX_DATAGRAM_SIZE		0x88
#define USB_CDC_GET_CRC_MODE			0x89
#define USB_CDC_SET_CRC_MODE			0x8a
*/

static int read_vend_cmd(struct handle *h, uint8_t req, uint16_t val, uint8_t *buf, size_t len)
{
	return libusb_control_transfer(
		h->devh,
		LIBUSB_ENDPOINT_IN | LIBUSB_REQUEST_TYPE_VENDOR | LIBUSB_RECIPIENT_INTERFACE,
        req,
		val,
		h->ifc,
        buf,
		len,
		1000
	);
}

static int write_vend_cmd(struct handle *h, uint8_t req, uint16_t val, uint8_t *buf, size_t len)
{
	return libusb_control_transfer(
		h->devh,
		LIBUSB_ENDPOINT_OUT | LIBUSB_REQUEST_TYPE_VENDOR | LIBUSB_RECIPIENT_INTERFACE,
        req,
		val,
		h->ifc,
        buf,
		len,
		1000
	);
}

static int mdio_read(struct handle *h, uint8_t reg_off, uint16_t *pv)
{
	uint8_t buf[sizeof(*pv)];
	int     st;
	if ( (st = read_vend_cmd(h, VENDOR_CMD_MDIO_RW, (h->phy << 8 ) | (reg_off & 0x1f), buf, sizeof(buf) )) < sizeof(buf) ) {
		if ( st >= 0 ) {
			st = -1;
		}
		return st;
	}
	*pv = ( buf[1] << 8 ) | buf[0];
	return 0;
}

static int mdio_write(struct handle *h, uint8_t reg_off, uint16_t v)
{
	uint8_t buf[sizeof(v)];
	int     st;
	buf[0] =  v & 0xff;
	buf[1] = (v >> 8);
	if ( (st = write_vend_cmd(h, VENDOR_CMD_MDIO_RW, (h->phy <<8 ) | (reg_off & 0x1f), buf, sizeof(buf) )) < sizeof(buf) ) {
		if ( st >= 0 ) {
			st = -1;
		}
		return st;
	}
	return 0;
}

static void usage(const char *nm, int lvl)
{
	printf("usage: %s [-l <bufsz>] [-P <idProduct>] [-M <bytes>] [-S <macaddr>] [-G] [-h] %s [reg[=val]],...\n", nm, (lvl > 0 ? "[-V <idVendor>] [-i <phy_index>] [-s <stream_len>] [-f <filter>]" : "") );
    printf("Testing USB DCDAcm Example Using libusb\n");
    printf("  -h                 : this message (repeated -h increases verbosity of help)\n");
    printf("  -l <bufsz>         : set buffer size (default = max)\n");
    printf("  -P<idProduct>      : use product ID <idProduct> (default: 0x%04x)\n", ID_PROD);
	printf("  -M <byte>{,<byte>} : set MC filters\n");
	printf("  -S <hex_eth_addr>  : set mac address\n");
	printf("  -G                 : get mac address\n");
	if ( lvl > 0 ) {
    printf("  -V<idVendor>       : use vendor ID <idVendor> (default: 0x%04x)\n", ID_VEND);
    printf("  -i<phy_idx>        : phy index/address (default: %d)\n", PHY_IDX );
    printf("  -s<strm_len>       : test streaming firmware feature (default %d; 0 is off)\n", STRM_LEN);
    printf("  -f<filter>         : set packet filter flags\n");
	}
    printf("  reg[=val]          : read/write MDIO register\n");
}

int
main(int argc, char **argv)
{
struct handle                                    hndl;
libusb_context                                  *ctx   = 0;
int                                              rv    = 1;
int                                              st;
struct libusb_config_descriptor                 *cfg   = 0;
int                                              i, got;
unsigned char                                    buf[1024];
int                                              opt;
int                                              len  =  0;
int                                             *i_p;
int                                              vid  = ID_VEND;
int                                              pid  = ID_PROD;
int                                              help = -1;
unsigned long                                   *l_p;
enum libusb_speed                                spd;
uint16_t                                         val;
int                                              reg;
int                                              strm_len = 0;
uint8_t                                         *bufp = 0;
const char                                      *optstr = "l:hV:P:i:s:f:M:S:G";
int                                              defaultAction = 1;

	handle_init( &hndl );

	while ( (opt = getopt(argc, argv, optstr )) > 0 ) {
		i_p = 0;
		l_p = 0;
		switch (opt)  {
            case 'h':  help++;             break;
			case 'l':  i_p = &len;         break;
            case 'V':  i_p = &vid ;        break;
            case 'P':  i_p = &pid ;        break;
			case 'i':  i_p = &hndl.phy;    break;
			case 's':  i_p = &strm_len;    break;

			case 'f': /* fall thru */
			case 'M': /* fall thru */
			case 'S': /* fall thru */
			case 'G': /* fall thru */
                defaultAction = 0;
				break;
			default:
				fprintf(stderr, "Error: Unknown option -%c\n", opt);
                usage( argv[0], 0 );
				goto bail;
		}
		if ( i_p && 1 != sscanf(optarg, "%i", i_p) ) {
			fprintf(stderr, "Unable to scan option -%c arg\n", opt);
			goto bail;
		}
		if ( l_p && 1 != sscanf(optarg, "%li", l_p) ) {
			fprintf(stderr, "Unable to scan option -%c arg\n", opt);
			goto bail;
		}
	}

    if ( help >= 0 ) {
		usage( argv[0], help );
		return 0;
	}

	if ( hndl.phy > 31 ) {
		fprintf(stderr,"Error: invalid phy idx\n");
		goto bail;
	}

	if ( len < 0 || len > sizeof(buf) ) {
		fprintf(stderr, "Invalid length\n");
		goto bail;
	}

	st = libusb_init( &ctx );
	if ( st ) {
		fprintf(stderr, "libusb_init: %i\n", st);
		goto bail;
	}

	hndl.devh = libusb_open_device_with_vid_pid( ctx, vid, pid );
	if ( ! hndl.devh ) {
		fprintf(stderr, "libusb_open_device_with_vid_pid: not found\n");
		goto bail;
	}

	spd = libusb_get_device_speed( libusb_get_device( hndl.devh ) );
	switch ( spd ) {
    	case LIBUSB_SPEED_FULL:
			printf("Full-");
		break;
    	case LIBUSB_SPEED_HIGH:
			printf("High-");
		break;
        default:
			fprintf(stderr, "Error: UNKOWN/unsupported (%i) Speed device\n", spd);
			goto bail;
	}
	printf("speed device.\n");


	if ( libusb_set_auto_detach_kernel_driver( hndl.devh, 1 ) ) {
		fprintf(stderr, "libusb_set_auto_detach_kernel_driver: failed\n");
		goto bail;
	}

    st = libusb_get_active_config_descriptor( libusb_get_device( hndl.devh ), &cfg );
	if ( st ) {
		fprintf(stderr, "libusb_get_active_config_descriptor: %i\n", st);
		goto bail;
	}

	hndl.ifc = -1;
	for ( i = 0; i < cfg->bNumInterfaces; i++ ) {
		if ( cfg->interface[i].num_altsetting < 1 ) {
			continue;
		}
		if (    USB_CLASS_COMM       == cfg->interface[i].altsetting[0].bInterfaceClass
		     && USB_CDC_SUBCLASS_NCM == cfg->interface[i].altsetting[0].bInterfaceSubClass ) {
			hndl.ifc = cfg->interface[i].altsetting[0].bInterfaceNumber;
			break;
		}
	}

	if ( -1 == hndl.ifc ) {
		fprintf(stderr, "CDC NCM interface not found\n");
		goto bail;
	} else {
		printf("CDC NCM has interface number %d\n", hndl.ifc);
	}

	st = libusb_claim_interface( hndl.devh, hndl.ifc );
	if ( st ) {
		fprintf(stderr, "libusb_claim_interface: %i\n", st);
		hndl.ifc = -1;
		goto bail;
	}

	if ( argc <= optind && 0 == strm_len ) {
		if ( defaultAction ) {
			st = read_vend_cmd( &hndl, VENDOR_CMD_CMDSET_VERSION, 0x0000, buf, 4 );
			if ( st < 4 ) {
				fprintf(stderr, "Vendor request 0x00 failed: %d\n", st);
			} else {
				uint32_t reply = 0;
				for ( i = st - 1; i >= 0; i-- ) {
					reply = (reply<<8) | buf[i];
				}
				printf("Vendor request 0x00 (command-set version) reply: 0x%08x\n", reply);
			}

			i = 0x10;
			st = mdio_read( &hndl, i, &val );
			if ( st ) {
				fprintf(stderr, "mdio_read failed: %s\n", libusb_error_name( st ));
				goto bail;
			} else {
				printf("MDIO read of reg 0x%02x: 0x%04x\n", i, val);
			}
		}

	} else {
		for ( i = optind; i < argc; i++ ) {
			got = sscanf( argv[i], "%i=%hi", &reg, &val );
			if ( got < 1 ) {
				fprintf(stderr, "Unable to scan 'reg[=val]' from '%s'; skipping\n", argv[i]);
				continue;
			}
			if ( reg > 31 || reg < 0 ) {
				fprintf(stderr, "Invalid register '%s'; skipping\n", argv[i]);
				continue;
			}

			if ( 2 == got ) {
				printf("Writing 0x%02x: 0x%04x\n", reg, val);
				st = mdio_write( &hndl, reg, val );
			} else {
				st = mdio_read( &hndl, reg, &val );
			}
			if ( st ) {
				fprintf(stderr, "mdio_%s failed: %s\n", (2 == got ? "write" : "read"), libusb_error_name(st));
				goto bail;
			} else {
				if ( 1 == got ) {
					printf("MDIO read of reg 0x%02x: 0x%04x\n", reg, val);
				}
			}
		}
		if ( strm_len > 512 ) {
			strm_len = 512;
			fprintf(stderr, "Warning: stream length capped at %d\n", strm_len);
		}
		if ( strm_len > 0 ) {
			if ( ! (bufp=malloc(strm_len)) ) {
				fprintf(stderr, "Error: no memory|n");
				goto bail;
			}
			for ( i = 0; i < strm_len; i++ ) {
				bufp[i] = (i & 0xff);
			}

			st = write_vend_cmd(&hndl, VENDOR_CMD_STRM , 0x0000, bufp, strm_len);
			if ( st < strm_len ) {
				if ( st < 0 ) {
					fprintf(stderr, "Writing stream failed %s\n", libusb_error_name(st));
					goto bail;
				} else {
					fprintf(stderr, "Incomplete stream written: %d\n", st);
				}
			}
		}
	}

	optind = 0;
	while ( (opt = getopt(argc, argv, optstr )) > 0 ) {
		switch ( opt ) {
			case 'M':
			case 'f':
			case 'S':
			case 'G':
				if ( (st = clazz_cmd( &hndl, stdout, opt, optarg )) < 0 ) {
					fprintf(stderr, "USB control request failed (%d)\n", st);
					goto bail;
				}
			default:
				break;
		}
	}

	rv = 0;

bail:
	if ( cfg ) {
		libusb_free_config_descriptor( cfg );
	}
	if ( hndl.devh ) {
		if ( hndl.ifc >= 0 ) {
			libusb_release_interface( hndl.devh, hndl.ifc );
		}
		libusb_close( hndl.devh );
	}
	if ( ctx ) {
		libusb_exit( ctx );
	}
	free( bufp );
	return rv;
}
