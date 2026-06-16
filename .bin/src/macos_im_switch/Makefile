CC = clang
CFLAGS = -Wall -Wextra -std=c99
LDFLAGS = -framework Carbon -framework ApplicationServices

PREFIX = $(HOME)/.bin
TARGET = macos-im-switch

.PHONY: all clean install

all: $(TARGET)

$(TARGET): main.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<

install: $(TARGET)
	install -m 755 $(TARGET) $(PREFIX)/

clean:
	rm -f $(TARGET)
