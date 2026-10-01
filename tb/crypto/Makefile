# Makefile for all crypto tests
.PHONY: all sim clean

sim:
	$(MAKE) -f Makefile.ctr sim
	$(MAKE) -f Makefile.mac sim
	$(MAKE) -f Makefile.counter sim

clean:
	rm -rf sim_build_* results*.xml
