#include <stdio.h>
#include "platform.h"
#include "xil_printf.h"
#include "xil_io.h"

#define INPUT_WIDTH 100
#define INPUT_HEIGHT 100
#define INPUT_BYTES (INPUT_WIDTH * INPUT_HEIGHT)

// AXI GPIO 0: Dual Channel
#define GPIO_0_BASE 0x41200000
// Channel 1 DATA register: BASE + 0x0
// V0, H0, SW, SH, TW
#define GPIO_0_CH1_BASE (GPIO_0_BASE + 0x0)
// Channel 2 DATA register: BASE + 0x8
// TH, RST
#define GPIO_0_CH2_BASE (GPIO_0_BASE + 0x8)
// AXI GPIO 1: DONE input
#define GPIO_STATUS_BASE 0x41210000
// BRAM
#define BRAM0_BASE 0x40000000 // 原始圖片輸入 BRAM
#define BRAM1_BASE 0x42000000 // Bicubic 放大後的圖片輸出 BRAM

#define RST_BIT (1U << 6)
#define DONE_BIT (1U << 0)

// ==========================================
// Modular Design
// ==========================================
void init_hw_system()
{
    init_platform();

    u32 gpio_ch2 = Xil_In32(GPIO_0_CH2_BASE);
    gpio_ch2 |= RST_BIT;
    Xil_Out32(GPIO_0_CH2_BASE, gpio_ch2);

    Xil_printf("--- FPGA Bicubic Accelerator Ready ---\n");
}

void receive_dynamic_parameters(u32 *tw, u32 *th)
{
    *tw = (u32)inbyte();
    *th = (u32)inbyte();

    if (*tw < 2 || *tw > 63)
        *tw = 63;
    if (*th < 2 || *th > 63)
        *th = 63;
}

void configure_hw_registers(u32 v0, u32 h0, u32 sw, u32 sh, u32 tw, u32 th)
{
    // 將 GPIO_0 參數打包
    u32 gpio0_val = (v0 & 0x7F) |
                    ((h0 & 0x7F) << 7) |
                    ((sw & 0x1F) << 14) |
                    ((sh & 0x1F) << 19) |
                    ((tw & 0x3F) << 24);

    Xil_Out32(GPIO_0_CH1_BASE, gpio0_val);

    u32 gpio_ch2 = Xil_In32(GPIO_0_CH2_BASE);
    gpio_ch2 &= ~0x3F;
    gpio_ch2 |= (th & 0x3F);

    Xil_Out32(GPIO_0_CH2_BASE, gpio_ch2);
}

void load_img_to_bram0(int input_size)
{
    for (int i = 0; i < input_size; i++)
    {
        u8 pixel_data = inbyte();
        Xil_Out8(BRAM0_BASE + i, pixel_data);
    }
}

void trigger_hw_fsm()
{
    u32 gpio_ch2 = Xil_In32(GPIO_0_CH2_BASE);
    // RST 進行硬體重置
    gpio_ch2 |= RST_BIT;
    Xil_Out32(GPIO_0_CH2_BASE, gpio_ch2);

    // 確保硬體狀態機完全歸零
    for (volatile int delay = 0;
         delay < 5000;
         delay++)
    {
    }

    // 解除重置，init -> start
    gpio_ch2 = Xil_In32(GPIO_0_CH2_BASE);
    gpio_ch2 &= ~RST_BIT;
    Xil_Out32(GPIO_0_CH2_BASE, gpio_ch2);
}

void wait_for_hw_done()
{
    while ((Xil_In32(GPIO_STATUS_BASE) & DONE_BIT) == 0)
    {
        // 等待硬體完成運算 (Polling)
    }
}

void stream_results_to_host(int output_size)
{
    print("\nSTART_OF_DATA\n");
    for (int i = 0; i < output_size; i++)
    {
        u8 result_pixel = Xil_In8(BRAM1_BASE + i);
        outbyte(result_pixel);
    }
    print("\nEND_OF_DATA\n");
}

// ==========================================
// 4. Main Function
// ==========================================
int main()
{
    // System Initialization
    init_hw_system();

    // 基礎參數設定
    u32 v0 = 0, h0 = 0;
    u32 sw = 31, sh = 31;
    u32 tw = 63, th = 63;

    while (1)
    {
        print("\nWAITING_FOR_IMG\n");

        receive_dynamic_parameters(&tw, &th);

        configure_hw_registers(v0, h0, sw, sh, tw, th);

        load_img_to_bram0(INPUT_BYTES);

        trigger_hw_fsm();

        wait_for_hw_done();

        int output_bytes = tw * th;
        stream_results_to_host(output_bytes);
    }

    return 0;
}