import serial
import numpy as np
import cv2
import tkinter as tk
from tkinter import ttk
from PIL import Image, ImageTk
import os

# =============================================================
# 參數配置區
# =============================================================
COM_PORT = 'COM3'     
BAUD_RATE = 115200
SRC_W, SRC_H = 31, 31  

class BicubicApp:
    def __init__(self, root):
        self.root = root
        self.root.title("支援多解析度輸出之雙三次影像縮放 FPGA 實作")
        self.root.geometry("850x550")
        self.root.configure(bg="#f5f6fa")

        # --- 介面標題 ---
        title = tk.Label(
            root,
            text="支援多解析度輸出之雙三次影像縮放 FPGA 實作",
            font=("Microsoft JhengHei", 22, "bold"),
            fg="#2f3640",
            bg="#f5f6fa"
        )
        title.pack(pady=15)

        # 多解析度切換控制列 
        control_frame = tk.Frame(root, bg="#f5f6fa")
        control_frame.pack(pady=5)
        tk.Label(
            control_frame,
            text="目標輸出解析度：",
            font=("Microsoft JhengHei", 11),
            bg="#f5f6fa"
        ).pack(side=tk.LEFT, padx=5)

        self.resolution_var = tk.StringVar(value="63x63")

        self.res_combobox = ttk.Combobox(
            control_frame,
            textvariable=self.resolution_var,
            values=["40x40", "50x50", "63x63"],
            width=10,
            state="readonly"
        )
        self.res_combobox.pack(side=tk.LEFT, padx=5)

        # 啟動按鈕
        self.btn = ttk.Button(root, text="啟動 FPGA 加速縮放", command=self.fetch_and_show)
        self.btn.pack(pady=10)

        # --- 影像顯示區塊 ---
        self.frame = tk.Frame(root, bg="#f5f6fa")
        self.frame.pack(pady=10)
        
        # Left：低解析度原圖
        self.lbl_src = tk.Label(self.frame, bg="#dcdde1")
        self.lbl_src.grid(row=0, column=0, padx=35)
        tk.Label(self.frame, text="放大前原始影像 ", font=("Microsoft JhengHei", 11), bg="#f5f6fa").grid(row=1, column=0, pady=5)
        
        # Right：Bicubic 放大圖
        self.lbl_tag = tk.Label(self.frame, bg="#dcdde1")
        self.lbl_tag.grid(row=0, column=1, padx=35)
        self.tag_title_var = tk.StringVar(value="Bicubic 放大影像 (63x63)")
        tk.Label(self.frame, textvariable=self.tag_title_var, font=("Microsoft JhengHei", 11, "bold"), fg="#4cd137", bg="#f5f6fa").grid(row=1, column=1, pady=5)
        
        # 狀態列
        self.status_var = tk.StringVar()
        self.status_var.set("系統就緒，等待連線...")
        tk.Label(root, textvariable=self.status_var, bd=1, relief=tk.SUNKEN, anchor=tk.W).pack(side=tk.BOTTOM, fill=tk.X)
        
        # =============================================================
        # 準備測試影像 
        # =============================================================
        img_path = 'roger.png'
        if os.path.exists(img_path):
            gray_img = cv2.imread(img_path, cv2.IMREAD_GRAYSCALE)
            self.src_np = cv2.resize(gray_img, (SRC_W, SRC_H), interpolation=cv2.INTER_AREA)
        else:
            self.src_np = np.zeros((SRC_H, SRC_W), dtype=np.uint8)
            cv2.circle(self.src_np, (16, 16), 12, 200, -1) 
            cv2.circle(self.src_np, (16, 16), 6, 50, -1)   
            
        self.update_canvas(self.src_np, self.lbl_src, use_smooth=False)

    def update_canvas(self, np_img, label_widget, use_smooth=False):
        """將影像放大顯示於 GUI 上"""
        interp_method = cv2.INTER_CUBIC if use_smooth else cv2.INTER_NEAREST
        cv_disp = cv2.resize(np_img, (250, 250), interpolation=interp_method)
        img_pil = Image.fromarray(cv_disp)
        img_tk = ImageTk.PhotoImage(image=img_pil)
        label_widget.config(image=img_tk)
        label_widget.image = img_tk

    def fetch_and_show(self):
        # 1. 取得使用者在介面上選取的目標解析度
        selected_res = self.resolution_var.get()
        tag_w, tag_h = map(int, selected_res.split('x'))
        
        # 更新右側標題
        self.tag_title_var.set(f"Bicubic 放大影像 ({tag_w}x{tag_h})")
        
        self.status_var.set(f"正在與 FPGA 通訊 (目標解析度: {tag_w}x{tag_h})...")
        self.root.update()

        ser = None
        
        try:
            # =====================================================
            # 2. 建立 UART 連線
            # =====================================================
            ser = serial.Serial(COM_PORT, BAUD_RATE, timeout=1.0)
            ser.reset_input_buffer()

            # =====================================================
            # 3. 傳送 TW / TH
            # =====================================================
            ser.write(bytes([tag_w, tag_h]))
            ser.flush()
            print(f"傳送 TW={tag_w}, TH={tag_h}")

            # =====================================================
            # 4. 傳送圖片
            # =====================================================
            self.status_var.set("正在將原圖傳送至 FPGA BRAM0...")
            self.root.update()
            bram_img = np.zeros((100, 100), dtype=np.uint8)
            padded = np.pad(self.src_np, ((1, 1), (1, 1)), mode='edge')
            bram_img[0:33, 0:33] = padded
            image_data = bram_img.tobytes()
            ser.write(image_data)
            ser.flush()
            print(f"已傳送 {len(image_data)} Bytes")
            
            # =====================================================
            # 5. 等待 FPGA 運算完成
            # =====================================================
            self.status_var.set("FPGA Bicubic 運算中...")
            self.root.update()
                
            start_received = False

            for _ in range(100):
                line = ser.readline()
                if b"START_OF_DATA" in line:
                    start_received = True
                    break
            
            if not start_received:
                raise Exception("沒有收到 START_OF_DATA")
            
            print("收到 START_OF_DATA")
            # =====================================================
            # 6. 接收 FPGA 輸出影像
            # =====================================================
            expected_size = tag_w * tag_h
            raw_data = bytearray()

            while len(raw_data) < expected_size:
                chunk = ser.read(expected_size - len(raw_data))
                if not chunk:
                    raise Exception("接收 FPGA 輸出逾時")

                raw_data.extend(chunk)
            raw_data = bytes(raw_data)

            print(
                f"收到 {len(raw_data)} / "
                f"{expected_size} Bytes"
            )

            if len(raw_data) != expected_size:
                raise Exception(
                    f"輸出資料長度錯誤："
                    f"{len(raw_data)} != "
                    f"{expected_size}"
                )
             # =====================================================
            # 7. 將 Binary 轉回影像
            # =====================================================
            tag_np = np.frombuffer(
                raw_data,
                dtype=np.uint8
            ).reshape(
                (tag_h, tag_w)
            )
            
            # =====================================================
            # 8. 顯示 FPGA 實際輸出
            # =====================================================
            self.update_canvas(tag_np, self.lbl_tag, use_smooth=False)
            self.status_var.set(f"FPGA Bicubic 運算完成！ ({tag_w}x{tag_h})")
            print("FPGA Bicubic 運算完成")

        except Exception as e:
            print("通訊中斷或異常:", e)
            self.status_var.set(f"通訊中斷或異常: {e}")
        
        finally:
            if ser is not None and ser.is_open:
                ser.close()

if __name__ == "__main__":
    root = tk.Tk()
    app = BicubicApp(root)
    root.mainloop()