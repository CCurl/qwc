ARCH ?= 64
CFLAGS = -m$(ARCH) -O3

qwc: *.c *.h
	$(CC) $(CFLAGS) -o qwc *.c
	ls -l qwc

clean:
	rm -f qwc

run: qwc
	./qwc

bin: qwc qwc-boot.fth
	cp -u -p qwc ~/bin/
	cp -u -p qwc-boot.fth ~/bin/
