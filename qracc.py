import numpy as np
import os

# =========================================================
# 1. 路徑設定 (請根據你的伺服器環境修改 BASE_DIR)
# =========================================================
# 假設你的專案根目錄在 /home/user111/qr
BASE_DIR = r"C:\Users\naizh\Desktop\qr" 
INPUT_PATH = os.path.join(BASE_DIR, "pat_A.dat")

# =========================================================
# 2. 高精度 CORDIC 核心 (64-bit Floating-point)
# =========================================================
def float_cordic_vectoring(x, y, iterations=64):
    K = 1.0
    dirs = []
    for i in range(iterations):
        K *= np.sqrt(1 + 2**(-2*i))
        if y < 0:
            d = 1
            x_next = x - y * (2**(-i))
            y_next = y + x * (2**(-i))
        else:
            d = -1
            x_next = x + y * (2**(-i))
            y_next = y - x * (2**(-i))
        x, y = x_next, y_next
        dirs.append(d)
    return x/K, y/K, dirs

def float_cordic_rotation(x, y, dirs):
    iterations = len(dirs)
    K = 1.0
    for i in range(iterations):
        K *= np.sqrt(1 + 2**(-2*i))
        d = dirs[i]
        if d == 1:
            x_next = x - y * (2**(-i))
            y_next = y + x * (2**(-i))
        else:
            x_next = x + y * (2**(-i))
            y_next = y - x * (2**(-i))
        x, y = x_next, y_next
    return x/K, y/K

# =========================================================
# 3. 檔案解析與運算邏輯
# =========================================================
def hex_to_signed_int8(hex_str):
    val = int(hex_str, 16)
    return val - 256 if val > 127 else val

def run_verification():
    if not os.path.isabs(INPUT_PATH):
        print(f"[警告] 當前路徑不是絕對路徑: {INPUT_PATH}")
    
    if not os.path.exists(INPUT_PATH):
        print(f"[錯誤] 找不到檔案，請檢查路徑: {INPUT_PATH}")
        return

    print(f"📂 正在讀取檔案: {INPUT_PATH}")
    
    patterns = []
    current_matrix = []
    with open(INPUT_PATH, 'r') as f:
        for line in f:
            line = line.split('//')[0].strip()
            if not line: continue
            row_data = [hex_to_signed_int8(line[i:i+2]) for i in range(0, 8, 2)]
            current_matrix.append(row_data)
            if len(current_matrix) == 4:
                patterns.append(np.array(current_matrix))
                current_matrix = []

    print(f"✅ 成功載入 {len(patterns)} 組矩陣。")
    idx = input("請輸入欲查看的 Pattern ID (0-99): ").strip()
    
    try:
        p_id = int(idx)
        A = patterns[p_id].astype(float)
        
        # 模擬脈動陣列 [A | I]
        M = np.hstack((A, np.eye(4)))
        R_res = np.zeros((4, 8))
        
        for k in range(4):
            y_row = M[k, :].copy()
            for r in range(4):
                x_new, y_new, dirs = float_cordic_vectoring(R_res[r, r], y_row[r])
                R_res[r, r] = x_new
                y_row[r] = y_new
                for c in range(r + 1, 8):
                    xc_new, yc_new = float_cordic_rotation(R_res[r, c], y_row[c], dirs)
                    R_res[r, c] = xc_new
                    y_row[c] = yc_new

        print(f"\n--- Pattern {p_id} 高精度 CORDIC 分析 (無截斷) ---")
        print("R Matrix (精確解):")
        print(np.round(R_res[:, :4], 6))
        print("\nQ^T Matrix (精確解):")
        print(np.round(R_res[:, 4:], 6))
        
        # 標準 NumPy QR 作為終極對照
        Q_np, R_np = np.linalg.qr(A)
        print("\n[對照] NumPy 標準庫 R:")
        print(np.round(R_np, 6))

    except Exception as e:
        print(f"執行出錯: {e}")

if __name__ == "__main__":
    run_verification()