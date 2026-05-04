# Simple Makefile for on-board or cross-compilation

# Default to gcc (native compilation on DE10)
# To cross-compile, run: make CC=arm-linux-gnueabihf-gcc
CC ?= gcc
CFLAGS = -g -Wall -O2
LDFLAGS = -lrt

# Source files
SRCS = main.c LCD_Hw.c LCD_Driver.c LCD_Lib.c lcd_graphic.c font.c terasic_lib.c render_screen.c
OBJS = $(SRCS:.c=.o)
TARGET = lcd_msg_app

# Rules
all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $^

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(OBJS) $(TARGET)

# Test build (PC-side, native gcc)
TEST_TARGET  ?= lcd_msg_test.exe
TEST_CFLAGS  = -g -Wall -O0 -DUNIT_TEST -I. -Itest
TEST_SRCS    = render_screen.c \
               test/mock_lcd.c \
               test/test_lcd_render.c

MSYS2_BASH := /mnt/c/msys64/usr/bin/bash.exe
# Convert /mnt/c/foo -> /c/foo for MSYS2
MSYS2_DIR  := $(shell echo "$(CURDIR)" | sed 's|^/mnt/\([a-zA-Z]\)|/\1|')

test: $(TEST_TARGET)

$(TEST_TARGET): $(TEST_SRCS)
	$(MSYS2_BASH) -lc 'export MSYSTEM=UCRT64; \
	  source /etc/profile; \
	  cd "$(MSYS2_DIR)" && \
	  gcc.exe $(TEST_CFLAGS) -o $(TEST_TARGET) $(TEST_SRCS)'

test-run: $(TEST_TARGET)
	cmd.exe /c $(TEST_TARGET)

test-clean:
	rm -f $(TEST_TARGET)

.PHONY: test test-run test-clean
