
TESTS=RMIIMacTxTb

tests: $(TESTS)

VPATH=../hdl

%.o: %.vhd
	ghdl -a $<

%Tb: %Tb.o
	ghdl -e -Wl,-no-pie -o $@  $@

RMIIMacTxTb.o: RMIIMacTx.o RMIIMacRx.o

RMIIMacTx.o: RMIIMacPkg.o

RMIIMacRx.o: RMIIMacPkg.o

clean:
	$(RM) *.o $(TESTS) work-obj*.cf

