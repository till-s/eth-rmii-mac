
TESTS=RMIIMacTxTb RMIIMacRxTb

tests: $(TESTS)

VPATH=../hdl

%.o: %.vhd
	ghdl -a $<

%Tb: %Tb.o
	ghdl -e -Wl,-no-pie -o $@  $@

RMIIMacTxTb.o: RMIIMacTx.o
RMIIMacRxTb.o: RMIIMacRx.o RMIIMacPkg.o

RMIIMacTx.o: RMIIMacPkg.o

RMIIMacRx.o: RMIIMacPkg.o

clean:
	$(RM) *.o $(TESTS) work-obj*.cf

