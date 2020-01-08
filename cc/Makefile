
BUILDDIR = ../bin


PROGRAMS = $(BUILDDIR)/pcb2ver $(BUILDDIR)/bin2m $(BUILDDIR)/bin2raw $(BUILDDIR)/drop1 $(BUILDDIR)/raw2wav $(BUILDDIR)/cen_gen

all: dir $(PROGRAMS)

dir:
	mkdir -p $(BUILDDIR)


$(BUILDDIR)/pcb2ver: pcb2ver.cc
	$(CXX) -o $@ pcb2ver.cc

$(BUILDDIR)/bin2m: bin2m.cc
	$(CXX) -o $@ bin2m.cc

$(BUILDDIR)/bin2raw: bin2raw.cc
	$(CXX) -o $@ bin2raw.cc

$(BUILDDIR)/cen_gen: cen_gen.cc
	$(CXX) -o $@ cen_gen.cc

$(BUILDDIR)/drop1: drop1.cc
	$(CXX) -o $@ drop1.cc

WaveWritter.o: WaveWritter.cpp

$(BUILDDIR)/raw2wav : raw2wav.cc WaveWritter.o
	$(CXX) -o $@ raw2wav.cc WaveWritter.o

clean:
	rm -f *.o $(PROGRAMS)

