#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>

#include "lcd_graphic.h"
#include "LCD_Lib.h"
#include "font.h"

static LCD_CANVAS gCanvas;
static uint8_t gFrameBuffer[128 * 8];
static bool gCanvasInit = false;

void DRAW_Pixel(LCD_CANVAS *pCanvas, int X, int Y, int Color) {
    int nLine;
    uint8_t *pFrame, Mask;

    if (X < 0 || X >= pCanvas->Width || Y < 0 || Y >= pCanvas->Height)
        return;

    nLine = Y >> 3;
    Mask = 0x01 << (Y % 8);
    pFrame = pCanvas->pFrame + pCanvas->Width * nLine + X;
    
    if (Color == 0x00)
        *pFrame &= ~Mask;
    else
        *pFrame |= Mask;
}

void DRAW_Refresh(LCD_CANVAS *pCanvas) {
    LCD_FrameCopy(pCanvas->pFrame);
}

void DRAW_Line(LCD_CANVAS *pCanvas, int X1, int Y1, int X2, int Y2, int Color) {
    int dx, dy, sx, sy, err, e2;
    
    dx = abs(X2 - X1);
    dy = abs(Y2 - Y1);
    sx = (X1 < X2) ? 1 : -1;
    sy = (Y1 < Y2) ? 1 : -1;
    err = dx - dy;
    
    while (1) {
        DRAW_Pixel(pCanvas, X1, Y1, Color);
        if (X1 == X2 && Y1 == Y2) break;
        e2 = 2 * err;
        if (e2 > -dy) { err -= dy; X1 += sx; }
        if (e2 < dx) { err += dx; Y1 += sy; }
    }
}

void DRAW_Rect(LCD_CANVAS *pCanvas, int X1, int Y1, int X2, int Y2, int Color) {
    DRAW_Line(pCanvas, X1, Y1, X2, Y1, Color);
    DRAW_Line(pCanvas, X2, Y1, X2, Y2, Color);
    DRAW_Line(pCanvas, X2, Y2, X1, Y2, Color);
    DRAW_Line(pCanvas, X1, Y2, X1, Y1, Color);
}

void DRAW_Circle(LCD_CANVAS *pCanvas, int x0, int y0, int Radius, int Color) {
    int x = Radius, y = 0;
    int radiusError = 1 - x;

    while (x >= y) {
        DRAW_Pixel(pCanvas, x + x0, y + y0, Color);
        DRAW_Pixel(pCanvas, y + x0, x + y0, Color);
        DRAW_Pixel(pCanvas, -x + x0, y + y0, Color);
        DRAW_Pixel(pCanvas, -y + x0, x + y0, Color);
        DRAW_Pixel(pCanvas, -x + x0, -y + y0, Color);
        DRAW_Pixel(pCanvas, -y + x0, -x + y0, Color);
        DRAW_Pixel(pCanvas, x + x0, -y + y0, Color);
        DRAW_Pixel(pCanvas, y + x0, -x + y0, Color);
        y++;
        if (radiusError < 0)
            radiusError += 2 * y + 1;
        else {
            x--;
            radiusError += 2 * (y - x) + 1;
        }
    }
}

void DRAW_Clear(LCD_CANVAS *pCanvas, int nValue) {
    memset(pCanvas->pFrame, nValue ? 0xFF : 0x00, pCanvas->FrameSize);
}

void DRAW_PrintChar(LCD_CANVAS *pCanvas, int X0, int Y0, char Text, int Color, FONT_TABLE *font_table) {
    unsigned char *pFont;
    uint8_t Mask;
    int x, y, p;

    for (y = 0; y < 2; y++) {
        Mask = 0x01;
        for (p = 0; p < 8; p++) {
            pFont = font_table->pBitmap[(unsigned char)Text][y];
            for (x = 0; x < 16; x++) {
                if (Mask & *pFont) {
                    DRAW_Pixel(pCanvas, X0 + x, Y0 + y * 8 + p, Color);
                } else {
                    // *** THIS LINE WAS MISSING - Clear background pixels ***
                    DRAW_Pixel(pCanvas, X0 + x, Y0 + y * 8 + p, 0);
                }
                pFont++;
            }
            Mask <<= 1;
        }
    }
}

void DRAW_PrintString(LCD_CANVAS *pCanvas, int X0, int Y0, char *pText, int Color, FONT_TABLE *font_table) {
    int nLen = strlen(pText);
    for (int i = 0; i < nLen; i++) {
        DRAW_PrintChar(pCanvas, X0 + i * font_table->FontWidth, Y0, pText[i], Color, font_table);
    }
}

static void InitCanvas(void) {
    if (!gCanvasInit) {
        gCanvas.Width = 128;
        gCanvas.Height = 64;
        gCanvas.FrameSize = 128 * 8;
        gCanvas.pFrame = gFrameBuffer;
        memset(gFrameBuffer, 0x00, sizeof(gFrameBuffer));
        gCanvasInit = true;
    }
}

void LCD_TextOut(int x, int y, char *text) {
    InitCanvas();
    DRAW_PrintString(&gCanvas, x, y, text, 1, &font_16x16);
    DRAW_Refresh(&gCanvas);
}

void LCD_GraphicClear(void) {
    printf("    [LCD_GraphicClear] Clearing buffer...\n");
    InitCanvas();
    memset(gFrameBuffer, 0x00, sizeof(gFrameBuffer));
    printf("    [LCD_GraphicClear] Buffer cleared, refreshing display...\n");
    DRAW_Refresh(&gCanvas);
    printf("    [LCD_GraphicClear] Done.\n");
}