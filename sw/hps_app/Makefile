# Simple Makefile for on-board or cross-compilation

# Default to gcc (native compilation on DE10).
# You can still override this on the command line, e.g.:
#   make CC=arm-linux-gnueabihf-gcc
CC = gcc
CFLAGS = -std=gnu99 -g -Wall -O2
LDFLAGS = -lrt

# Source files
SRCS = main.c LCD_Hw.c LCD_Driver.c LCD_Lib.c lcd_graphic.c font.c terasic_lib.c
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

.PHONY: all clean
