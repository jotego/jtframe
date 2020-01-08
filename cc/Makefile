
BUILDDIR = ../bin


PROGRAMS = $(BUILDDIR)/pcb2ver $(BUILDDIR)/bin2m $(BUILDDIR)/bin2raw $(BUILDDIR)/drop1 $(BUILDDIR)/raw2wav $(BUILDDIR)/cen_gen

all: dir $(PROGRAMS)

dir:
	mkdir -p $(BUILDDIR)


$(BUILDDIR)/pcb2ver:  $:
	$(CXX) -o $@ pcb2ver.cc

$(BUILDDIR)/bin2m:  $:
	$(CXX) -o $@ bin2m.cc

$(BUILDDIR)/bin2raw:  $:
	$(CXX) -o $@ bin2raw.cc

$(BUILDDIR)/cen_gen:  $:
	$(CXX) -o $@ cen_gen.cc

$(BUILDDIR)/drop1:  $:
	$(CXX) -o $@ drop1.cc

WaveWritter.o:

$(BUILDDIR)/raw2wav :  $: WaveWritter.o
	$(CXX) -o $@ raw2wav.cc WaveWritter.o


clean:
	rm -f *.o $(PROGRAMS)

