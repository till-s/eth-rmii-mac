
TESTS=RMIIMacTxTb

tests: $(TESTS)

VPATH=../hdl

%.o: %.vhd
	ghdl -a $<

%Tb: %Tb.o
	ghdl -e -Wl,-no-pie -o $@  $@

RMIIMacTxTb.o: RMIIMacTx.o

clean:
	$(RM) *.o $(TESTS) work-obj*.cf

