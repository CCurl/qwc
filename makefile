ARCH ?= 64
CFLAGS = -m$(ARCH) -O3

qwc: *.c *.h
	$(CC) $(CFLAGS) -o qwc *.c
	ls -l qwc

clean:
	rm -f qwc

run: qwc
	./qwc

bin: qwc
	cp -u -p qwc ~/bin/

boot: qwc-boot.fth
	cp -u -p qwc-boot.fth ~/bin/
