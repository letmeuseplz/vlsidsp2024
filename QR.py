import numpy as np

# =========================================================
# 1. 參數設定 (與硬體規格完全對齊)
# =========================================================
PAT_NUM = 100            # 產生 100 筆測資
FRAC_R  = 2              # R 矩陣 Q10.2 (放大 4 倍)
FRAC_Q  = 10             # Q 矩陣 Q2.10 (放大 1024 倍)
INT_W   = 12             # 硬體暫存器寬度 12-bit

np.random.seed(42)       # 固定隨機種子

# =========================================================
# 2. 模擬 Verilog 物理特性的輔助函式
# =========================================================
def trunc_12b(val):
    """ 模擬 12-bit 二補數的溢位 (Wrap-around) """
    # 範圍: -2048 ~ 2047
    return ((int(val) + 2048) % 4096) - 2048

def to_hex(val, bits):
    """ 將數值轉為 Hex 字串 """
    if bits == 8:
        v = int(val) & 0xFF
        return f"{v:02X}"
    else: # 12-bit
        v = int(val) & 0xFFF
        return f"{v:03X}"

def apply_norm(val):
    """ 
    Scaling Factor 補償: 1/K ≈ 0.60725
    公式: v * (1 - 2^-1 + 2^-3 - 2^-6 - 2^-9)
    使用恢復式減法以保持奇數精度
    """
    v = int(val)
    ans =  (v >> 1) + (v >> 3) - (v >> 6) - (v >> 9)
    return trunc_12b(ans)

# =========================================================
# 3. Bit-True CORDIC PE 模組
# =========================================================
def cordic_vectoring_pe(x_in, y_in):
    x, y = int(x_in), int(y_in)
    dirs = []
    for i in range(12):
        if y < 0:
            d = 1
            x_next = trunc_12b(x - (y >> i))
            y_next = trunc_12b(y + (x >> i))
        else:
            d = -1
            x_next = trunc_12b(x + (y >> i))
            y_next = trunc_12b(y - (x >> i))
        x, y = x_next, y_next
        dirs.append(d)
    return apply_norm(x), apply_norm(y), dirs

def cordic_rotation_pe(x_in, y_in, dirs):
    x, y = int(x_in), int(y_in)
    for i in range(12):
        if dirs[i] == 1:
            x_next = trunc_12b(x - (y >> i))
            y_next = trunc_12b(y + (x >> i))
        else:
            x_next = trunc_12b(x + (y >> i))
            y_next = trunc_12b(y - (x >> i))
        x, y = x_next, y_next
    return apply_norm(x), apply_norm(y)

# =========================================================
# 4. 主程式：生成、對比、分析
# =========================================================
print(f"| Pat | R Max Err (LSB) | Q Max Err (LSB) | Result |")
print(f"|-----|-----------------|-----------------|--------|")

total_max_r = 0
total_max_q = 0

with open("pat_A.dat", "w") as fa, \
     open("golden_R.dat", "w") as fr, \
     open("golden_Q.dat", "w") as fq:

    for p in range(PAT_NUM):
        # A. 生成輸入矩陣
        A = np.random.randint(-128, 128, size=(4, 4))
        
        # B. 準備硬體輸入資料 (Systolic Array 擴展矩陣 [A | I])
        M_A = A * (1 << FRAC_R)
        M_I = np.eye(4, dtype=int) * (1 << FRAC_Q)
        M = np.hstack((M_A, M_I)) 
        
        R_bt = np.zeros((4, 8), dtype=int) # Bit-true 結果暫存
        
        # C. 模擬硬體運算流程
        for k in range(4):
            y_row = M[k, :].copy()
            for r in range(4):
                # 對角線 PE (Vectoring)
                x_new, y_new, dirs = cordic_vectoring_pe(R_bt[r, r], y_row[r])
                R_bt[r, r] = x_new
                y_row[r] = y_new
                # 非對角線 PE (Rotation)
                for c in range(r + 1, 8):
                    xc_new, yc_new = cordic_rotation_pe(R_bt[r, c], y_row[c], dirs)
                    R_bt[r, c] = xc_new
                    y_row[c] = yc_new

        # D. 精確版對照 (NumPy 64-bit Float)
        Q_f, R_f = np.linalg.qr(A)
        R_ref = np.round(R_f * (1 << FRAC_R)).astype(int)
        Q_ref = np.round(Q_f.T * (1 << FRAC_Q)).astype(int) # 硬體輸出 Q^T
        
        # E. 誤差分析
        err_r = np.max(np.abs(R_bt[:, :4] - R_ref))
        err_q = np.max(np.abs(R_bt[:, 4:] - Q_ref))
        total_max_r = max(total_max_r, err_r)
        total_max_q = max(total_max_q, err_q)
        
        status = "PASS" if err_r <= 6 else "FAIL"
        print(f"| {p:02d}  |       {err_r:2d}        |       {err_q:2d}        |  {status}  |")

        # F. 寫入測資檔案
        for row in range(4):
            # pat_A.dat (8-bit * 4)
            fa.write("".join([to_hex(A[row, c], 8) for c in range(4)]) + f" // Pat:{p}\n")
            # golden_R.dat (12-bit * 4)
            fr.write("".join([to_hex(R_bt[row, c], 12) for c in range(4)]) + f" // Pat:{p} Dec:{R_bt[row,:4].tolist()}\n")
            # golden_Q.dat (12-bit * 4)
            fq.write("".join([to_hex(R_bt[row, c+4], 12) for c in range(4)]) + f" // Pat:{p} Dec:{R_bt[row,4:].tolist()}\n")

print("\n" + "="*50)
print(f"✅ 全測資生成完畢！")
print(f"📊 總結報告：")
print(f"   R 矩陣總最大誤差: {total_max_r} LSB")
print(f"   Q 矩陣總最大誤差: {total_max_q} LSB")
print("="*50)