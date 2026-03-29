#include "xparameters.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xstatus.h"
#include "sleep.h"
#include "xuartps.h"

#define FRAME_LEN 16U

#define REG_CTRL 0x00U
#define REG_BUDGET 0x04U
#define REG_REQ 0x08U
#define REG_IO 0x0CU
#define REG_TEMP_A 0x10U
#define REG_TEMP_B 0x14U
#define REG_STATUS0 0x20U
#define REG_STATUS1 0x24U
#define REG_EFF 0x28U
#define REG_INPUT_ECHO 0x2CU
#define REG_SAMPLE_COUNTER 0x30U

#ifndef PWR_GOV_BASEADDR`
#ifdef XPAR_PWR_GOV_AXI_LITE_0_S_AXI_BASEADDR
#define PWR_GOV_BASEADDR XPAR_PWR_GOV_AXI_LITE_0_S_AXI_BASEADDR
#else
#define PWR_GOV_BASEADDR 0x43C00000U
#endif
#endif

#ifndef PWR_GOV_UART_DEVICE_ID
#ifdef XPAR_XUARTPS_0_DEVICE_ID
#define PWR_GOV_UART_DEVICE_ID XPAR_XUARTPS_0_DEVICE_ID
#else
#define PWR_GOV_UART_DEVICE_ID 0U
#endif
#endif

#define BRIDGE_HZ 5U

typedef struct
{
    XUartPs Uart;
    u16 FrameCounter;
    u32 ExpectTempReg;
    u8 EchoLayout;
} BridgeCtx;

static int uart_init(BridgeCtx *ctx)
{
    XUartPs_Config *cfg;

    cfg = XUartPs_LookupConfig(PWR_GOV_UART_DEVICE_ID);
    if (cfg == NULL)
    {
        return XST_FAILURE;
    }

    if (XUartPs_CfgInitialize(&ctx->Uart, cfg, cfg->BaseAddress) != XST_SUCCESS)
    {
        return XST_FAILURE;
    }

    XUartPs_SetBaudRate(&ctx->Uart, 115200U);
    XUartPs_SetOperMode(&ctx->Uart, XUARTPS_OPER_MODE_NORMAL);

    return XST_SUCCESS;
}

static inline u32 reg_read(u32 off)
{
    return Xil_In32(PWR_GOV_BASEADDR + off);
}

static inline void reg_write(u32 off, u32 val)
{
    Xil_Out32(PWR_GOV_BASEADDR + off, val);
}

static inline void reg_set_bit(u32 off, u32 bit, u32 val)
{
    u32 cur = reg_read(off);
    if (val != 0U)
    {
        cur |= (1U << bit);
    }
    else
    {
        cur &= ~(1U << bit);
    }
    reg_write(off, cur);
}

static void handle_command(BridgeCtx *ctx, u8 cmd)
{
    u32 cur;

    if (ctx->ExpectTempReg != 0U)
    {
        reg_write(ctx->ExpectTempReg, (u32)(cmd & 0x7FU));
        ctx->ExpectTempReg = 0U;
        return;
    }

    if (cmd == 0xA0U)
    {
        reg_set_bit(REG_CTRL, 0U, 0U);
    }
    else if (cmd == 0xA1U)
    {
        reg_set_bit(REG_CTRL, 0U, 1U);
    }
    else if (cmd == 0xF0U)
    {
        reg_set_bit(REG_CTRL, 1U, 0U);
    }
    else if (cmd == 0xF1U)
    {
        reg_set_bit(REG_CTRL, 1U, 1U);
    }
    else if ((cmd >= 0xB0U) && (cmd <= 0xB7U))
    {
        reg_write(REG_BUDGET, (u32)(cmd & 0x07U));
    }
    else if ((cmd >= 0xC0U) && (cmd <= 0xC3U))
    {
        cur = reg_read(REG_REQ);
        cur = (cur & ~0x3U) | (u32)(cmd & 0x03U);
        reg_write(REG_REQ, cur);
    }
    else if ((cmd >= 0xC4U) && (cmd <= 0xC7U))
    {
        cur = reg_read(REG_REQ);
        cur = (cur & ~(0x3U << 2)) | ((u32)(cmd & 0x03U) << 2);
        reg_write(REG_REQ, cur);
    }
    else if (cmd == 0xD0U)
    {
        reg_set_bit(REG_IO, 0U, 0U);
    }
    else if (cmd == 0xD1U)
    {
        reg_set_bit(REG_IO, 0U, 1U);
    }
    else if (cmd == 0xD2U)
    {
        reg_set_bit(REG_IO, 1U, 0U);
    }
    else if (cmd == 0xD3U)
    {
        reg_set_bit(REG_IO, 1U, 1U);
    }
    else if (cmd == 0xD4U)
    {
        reg_set_bit(REG_IO, 2U, 0U);
    }
    else if (cmd == 0xD5U)
    {
        reg_set_bit(REG_IO, 2U, 1U);
    }
    else if (cmd == 0xD6U)
    {
        reg_set_bit(REG_IO, 3U, 0U);
    }
    else if (cmd == 0xD7U)
    {
        reg_set_bit(REG_IO, 3U, 1U);
    }
    else if (cmd == 0xE0U)
    {
        ctx->ExpectTempReg = REG_TEMP_A;
    }
    else if (cmd == 0xE1U)
    {
        ctx->ExpectTempReg = REG_TEMP_B;
    }
}

static void bridge_send_frame(BridgeCtx *ctx)
{
    u32 status0 = reg_read(REG_STATUS0);
    u32 status1 = reg_read(REG_STATUS1);
    u32 eff = reg_read(REG_EFF);
    u32 echo = reg_read(REG_INPUT_ECHO);

    u8 frame[FRAME_LEN];
    u8 csum = 0U;
    unsigned i;

    u8 host_mode = (u8)((status0 >> 0) & 0x1U);
    u8 alarm_a = (u8)((status0 >> 1) & 0x1U);
    u8 alarm_b = (u8)((status0 >> 2) & 0x1U);
    u8 clk_en_a = (u8)((status0 >> 3) & 0x1U);
    u8 clk_en_b = (u8)((status0 >> 4) & 0x1U);
    u8 grant_a = (u8)((status0 >> 5) & 0x3U);
    u8 grant_b = (u8)((status0 >> 7) & 0x3U);
    u8 phase = (u8)((status0 >> 9) & 0x7U);

    u8 current_budget = (u8)((status1 >> 0) & 0x7U);
    u8 budget_headroom = (u8)((status1 >> 3) & 0x7U);

    /* New (aligned) layout decode */
    u8 temp_a_new = (u8)((echo >> 0) & 0x7FU);
    u8 temp_b_new = (u8)((echo >> 8) & 0x7FU);
    u8 act_a_new = (u8)((echo >> 15) & 0x1U);
    u8 stall_a_new = (u8)((echo >> 16) & 0x1U);
    u8 act_b_new = (u8)((echo >> 17) & 0x1U);
    u8 stall_b_new = (u8)((echo >> 18) & 0x1U);
    u8 req_a_new = (u8)((echo >> 19) & 0x3U);
    u8 req_b_new = (u8)((echo >> 21) & 0x3U);

    /* Legacy packed layout decode */
    u8 temp_a_old = (u8)((echo >> 7) & 0x7FU);
    u8 temp_b_old = (u8)((echo >> 0) & 0x7FU);
    u8 act_a_old = (u8)((echo >> 14) & 0x1U);
    u8 stall_a_old = (u8)((echo >> 15) & 0x1U);
    u8 act_b_old = (u8)((echo >> 16) & 0x1U);
    u8 stall_b_old = (u8)((echo >> 17) & 0x1U);
    u8 req_a_old = (u8)((echo >> 18) & 0x3U);
    u8 req_b_old = (u8)((echo >> 20) & 0x3U);

    u8 temp_a;
    u8 temp_b;
    u8 act_a;
    u8 stall_a;
    u8 act_b;
    u8 stall_b;
    u8 req_a;
    u8 req_b;

    if (host_mode != 0U)
    {
        u32 host_req = reg_read(REG_REQ);
        u32 host_io = reg_read(REG_IO);
        u8 host_temp_a = (u8)(reg_read(REG_TEMP_A) & 0x7FU);
        u8 host_temp_b = (u8)(reg_read(REG_TEMP_B) & 0x7FU);
        u8 host_act_a = (u8)((host_io >> 0) & 0x1U);
        u8 host_stall_a = (u8)((host_io >> 1) & 0x1U);
        u8 host_act_b = (u8)((host_io >> 2) & 0x1U);
        u8 host_stall_b = (u8)((host_io >> 3) & 0x1U);
        u8 host_req_a = (u8)((host_req >> 0) & 0x3U);
        u8 host_req_b = (u8)((host_req >> 2) & 0x3U);
        unsigned score_new = 0U;
        unsigned score_old = 0U;

        if (temp_a_new != host_temp_a)
            score_new++;
        if (temp_b_new != host_temp_b)
            score_new++;
        if (act_a_new != host_act_a)
            score_new++;
        if (stall_a_new != host_stall_a)
            score_new++;
        if (act_b_new != host_act_b)
            score_new++;
        if (stall_b_new != host_stall_b)
            score_new++;
        if (req_a_new != host_req_a)
            score_new++;
        if (req_b_new != host_req_b)
            score_new++;

        if (temp_a_old != host_temp_a)
            score_old++;
        if (temp_b_old != host_temp_b)
            score_old++;
        if (act_a_old != host_act_a)
            score_old++;
        if (stall_a_old != host_stall_a)
            score_old++;
        if (act_b_old != host_act_b)
            score_old++;
        if (stall_b_old != host_stall_b)
            score_old++;
        if (req_a_old != host_req_a)
            score_old++;
        if (req_b_old != host_req_b)
            score_old++;

        ctx->EchoLayout = (score_old < score_new) ? 2U : 1U;

        /* In host mode, mirrors are authoritative and avoid echo-layout ambiguity. */
        temp_a = host_temp_a;
        temp_b = host_temp_b;
        act_a = host_act_a;
        stall_a = host_stall_a;
        act_b = host_act_b;
        stall_b = host_stall_b;
        req_a = host_req_a;
        req_b = host_req_b;
    }
    else if (ctx->EchoLayout == 2U)
    {
        temp_a = temp_a_old;
        temp_b = temp_b_old;
        act_a = act_a_old;
        stall_a = stall_a_old;
        act_b = act_b_old;
        stall_b = stall_b_old;
        req_a = req_a_old;
        req_b = req_b_old;
    }
    else
    {
        temp_a = temp_a_new;
        temp_b = temp_b_new;
        act_a = act_a_new;
        stall_a = stall_a_new;
        act_b = act_b_new;
        stall_b = stall_b_new;
        req_a = req_a_new;
        req_b = req_b_new;
    }

    frame[0] = 0xAAU;
    frame[1] = 0x55U;
    frame[2] = (u8)(ctx->FrameCounter & 0xFFU);
    frame[3] = (u8)((ctx->FrameCounter >> 8) & 0xFFU);
    frame[4] = (u8)(((clk_en_b << 4) | (clk_en_a << 3) | (alarm_b << 2) | (alarm_a << 1) | host_mode) & 0xFFU);
    frame[5] = (u8)(((grant_b << 2) | grant_a) & 0xFFU);
    frame[6] = (u8)(((budget_headroom << 3) | current_budget) & 0xFFU);
    frame[7] = (u8)(eff & 0xFFU);
    frame[8] = (u8)((eff >> 8) & 0x03U);
    frame[9] = temp_a;
    frame[10] = temp_b;
    frame[11] = (u8)(((act_b << 3) | (stall_b << 2) | (act_a << 1) | stall_a) & 0xFFU);
    frame[12] = (u8)(((req_b << 2) | req_a) & 0xFFU);
    frame[13] = (u8)(phase & 0x07U);

    for (i = 2U; i <= 13U; ++i)
    {
        csum ^= frame[i];
    }

    frame[14] = csum;
    frame[15] = 0x0DU;

    while (XUartPs_IsSending(&ctx->Uart) != 0U)
    {
        ;
    }
    (void)XUartPs_Send(&ctx->Uart, frame, FRAME_LEN);

    ctx->FrameCounter = (u16)(ctx->FrameCounter + 1U);
}

int main(void)
{
    BridgeCtx ctx;
    u8 rx_buf[64];
    u32 i;
    u32 bytes;

    ctx.FrameCounter = 0U;
    ctx.ExpectTempReg = 0U;
    ctx.EchoLayout = 0U;

    if (uart_init(&ctx) != XST_SUCCESS)
    {
        return XST_FAILURE;
    }

    xil_printf("PwrGov bare-metal bridge start\r\n");
    xil_printf("AXI base: 0x%08lx\r\n", (unsigned long)PWR_GOV_BASEADDR);

    for (;;)
    {
        bytes = (u32)XUartPs_Recv(&ctx.Uart, rx_buf, sizeof(rx_buf));
        for (i = 0U; i < bytes; ++i)
        {
            handle_command(&ctx, rx_buf[i]);
        }

        bridge_send_frame(&ctx);
        usleep(1000000U / BRIDGE_HZ);
    }
}
