# Simple RMII MAC

by Till Straumann, 2024.

## Introduction

This repository presents a very simple RMII mac which may be
useful for low-end FPGA applications to drive a Fast-Ethernet
PHY.

A driver for an MDIO interface is also included.

In addition, there is some logic that can interface the MDIO
driver to a [Mecatica](https://www.github.com/till-s/mecatica-usb)
control-endpoint agent as this project was created to
implement the [Tic-Nic](https://www.github.com/till-s/tic-nic).

## Features

 - Simple.
 - Supports padding of small-packets and CRC computation.
 - Multicast-filtering via 64-entry hash table (simple to modify
   for a different size).
 - dynamic MAC-address.
 - streaming data interface (no internal buffering).

### Buffering and Handshake

The design does not implement any buffering of ethernet data.
This means that the transmitter must be prepared to either
store data until successful transmission has ended (i.e., no
collision or other error has been detected) or be willing that
the packet be dropped.

The receiver may generate an 'abort' signal when an error is
detected after reception has started (e.g., withdrawal of user's
`rxRdy` signal or CRC error). The user must be prepared to
discard data when `rxAbort` is signalled. Note, however, that
the RX does have a small buffer capable of holding the destination
address, i.e., packet filtering is handled internally and never
results in `rxAbort` because a filtered packet is discarded
transparently.

#### TX Handshake

Transmission starts during the cycle when

      (txStrm.vld and txRdy) = '1'

i.e., the user must assert `vld` and wait until `txRdy` is detected.
Once the starting condition is met the user must keep supplying data
during every cycle `txRdy = '1'` and they *must not* withdraw `vld`.
During the cycle shipping the last byte both `vld` and `lst` must be
asserted.

Depending on whether the `appendCRC` bit is asserted on the control
port the TX pads short packets and (always) appends a CRC or it
skips these steps assuming the user has taken care.

#### RX Handshake

The user must signal readyness to accept data by asserting `rxRdy`.
If that happens during ongoing reception of a packet which started
prior to `rxRdy` being asserted then the RX discards the packet and
will only pass the next packet to the user.

Once `rxRdy` has been asserted it must not be withdrawn until
after `(lst and vld) = '1'` or `rxAbort` is detected. The user must
pick data bytes off the data port during every cycle when

      (rxStrm.vld and rxRdy) = '1'

Depending on whether the control port's `stripCRC` bit is set
or not the CRC is either stripped or passed to the user.

#### RX Filtering

The RX implements a simple packet filter

 - always accepts broadcast
 - always accepts unicast (the stations' own MAC address)
 - if `promisc` is set on the control port then all packets
   are accepted.
 - if `allmulti` is set on the control port then all multicast
   packets are accepted.
 - If the bit with the index that equals the hashed destination
   address is set in the `mcFilter` array is set (and the destination
   address *is* a multicast address) then the packet is accepted.

##### Multicast Hashing

The multicast hashing algorithm is the 6-bit CRC computed over
the destination address in little-endian order, i.e., in the
order the bits arrive at the station. The polynomial is

      110011

in little-endian notation with the msbit removed. The initial
value of the CRC is zero and no post inversion is performed.

A simple python script defining the precise algorithm can be
found in `scripts/mcHash.py`.

Note that an address in the common notation

      01:02:03:04:05:06

would have to be converted into a proper 48-bit little-endian
number

      0x060504030201

before being passed to the script. For this example the hash
is `59` (decimal) and the RX would accept a packet with this
destination address if it found `mcFilter(59) = '1'`.

## License

The RMII Mac is released under the [European-Union Public
License](https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12).

The EUPL permits including/merging/distributing the licensed code with
products released under some other licenses, e.g., the GPL variants.

I'm also open to use a different license.
