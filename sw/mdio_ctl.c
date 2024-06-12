/*
 * Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
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
	unsigned              phy;
};

static void
handle_init(struct handle *h)
{
	h->devh = NULL;
	h->ifc  = -1;
	h->phy  = PHY_IDX;
}

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
	if ( (st = read_vend_cmd(h, VENDOR_CMD_MDIO_RW, (h->phy << 8 ) | (reg_off & 0x1f), buf, sizeof(buf) )) < st ) {
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
	if ( (st = write_vend_cmd(h, VENDOR_CMD_MDIO_RW, (h->phy <<8 ) | (reg_off & 0x1f), buf, sizeof(buf) )) < st ) {
		if ( st >= 0 ) {
			st = -1;
		}
		return st;
	}
	return 0;
}



static void usage(const char *nm, int lvl)
{
	printf("usage: %s [-l <bufsz>] [-P <idProduct>] [-h] %s [reg[=val]],...\n", nm, (lvl > 0 ? "[-V <idVendor>] [-i <phy_index>] [-s <stream_len>]" : "") );
    printf("Testing USB DCDAcm Example Using libusb\n");
    printf("  -h           : this message (repeated -h increases verbosity of help)\n");
    printf("  -l <bufsz>   : set buffer size (default = max)\n");
    printf("  -P<idProduct>: use product ID <idProduct> (default: 0x%04x)\n", ID_PROD);
	if ( lvl > 0 ) {
    printf("  -V<idVendor> : use vendor ID <idVendor> (default: 0x%04x)\n", ID_VEND);
    printf("  -i<phy_idx>  : phy index/address (default: %d)\n", PHY_IDX );
    printf("  -s<strm_len> : test streaming firmware feature (default %d; 0 is off)\n", STRM_LEN);
    printf("  -f<filter>   : set packet filter flags\n");
	}
    printf("  reg[=val]    : read/write MDIO register\n");
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
int                                              filt = -1;

	handle_init( &hndl );

	while ( (opt = getopt(argc, argv, "l:hV:P:i:s:f:")) > 0 ) {
		i_p = 0;
		l_p = 0;
		switch (opt)  {
            case 'h':  help++;             break;
			case 'l':  i_p = &len;         break;
            case 'V':  i_p = &vid ;        break;
            case 'P':  i_p = &pid ;        break;
			case 'i':  i_p = &hndl.phy;    break;
			case 's':  i_p = &strm_len;    break;
			case 'f':  i_p = &filt;        break;
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

		st = read_vend_cmd( &hndl, 0x00, 0x0000, buf, 4 );
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

	if ( filt >= 0 ) {
		libusb_control_transfer(
			hndl.devh,
			LIBUSB_ENDPOINT_OUT | LIBUSB_REQUEST_TYPE_CLASS | LIBUSB_RECIPIENT_INTERFACE,
			USB_CDC_SET_ETHERNET_PACKET_FILTER,
			(filt & 0x1F),
			hndl.ifc,
			NULL,
			0,
			1000
		);
		sleep(10);
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
