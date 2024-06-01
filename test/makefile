

TESTS=RMIIMacTxTb RMIIMacRxTb EthMDIOTb Usb2Ep0MDIOCtlTb
MECATICA=/home/vivado/mecatica_efi

# EthMDIOTb does not actually test anything; just produces
# waveforms for manual inspection with gtkview...
test: build
	(for i in $(filter-out EthMDIOTb, $(TESTS)); do if ! ./$$i ; then exit 1; fi; done)

build: $(TESTS)

.PHONY: build test

VPATH=../hdl $(MECATICA)/core/hdl $(MECATICA)/endpoints/common/hdl

%.o: %.vhd
	ghdl -a $<

%Tb: %Tb.o
	ghdl -e -Wl,-no-pie -o $@  $@

RMIIMacTxTb.o: RMIIMacTx.o
RMIIMacRxTb.o: RMIIMacRx.o RMIIMacPkg.o

RMIIMacTx.o: RMIIMacPkg.o

RMIIMacRx.o: RMIIMacPkg.o

EthMDIOTb.o: EthMDIO.o

Usb2Ep0MDIOCtlTb.o: Usb2Ep0MDIOCtl.o

Usb2Ep0MDIOCtl.o: EthMDIO.o Usb2UtilPkg.o Usb2Pkg.o Usb2EpGenericCtlPkg.o Usb2EpGenericCtl.o

Usb2Pkg.o: Usb2UtilPkg.o

Usb2EpGenericCtlPkg.o: Usb2Pkg.o

Usb2EpGenericCtl.o: Usb2Pkg.o Usb2EpGenericCtlPkg.o

clean:
	$(RM) *.o $(TESTS) work-obj*.cf
