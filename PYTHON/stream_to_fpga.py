# File: stream_to_fpga.py
# Mo ta: Gui test pattern (gradient) tu PC den FPGA qua UDP
#        Format moi goi: [row_idx: 2B big-endian][640 bytes pixel Mono8]
# Ngay: 16/05/2026
# requirements: opencv-python, numpy

import socket
import struct
import time
import numpy as np
import cv2

# --- CONFIG ---
FPGA_IP   = "255.255.255.255"  # Broadcast
FPGA_PORT = 1234
WIDTH     = 640
HEIGHT    = 480
TARGET_FPS = 30

def generate_test_pattern(frame_num):
    """Tao anh test pattern gradient di chuyen theo thoi gian."""
    img = np.zeros((HEIGHT, WIDTH), dtype=np.uint8)

    # Gradient doc (tang dan tu tren xuong duoi)
    for y in range(HEIGHT):
        val = ((y + frame_num) * 255 // HEIGHT) % 256
        img[y, :] = val

    # Ve thanh trang doc o giua de kiem tra vi tri
    bar_x = (frame_num * 3) % WIDTH
    bar_w = 20
    x0 = max(0, bar_x - bar_w // 2)
    x1 = min(WIDTH, bar_x + bar_w // 2)
    img[:, x0:x1] = 255

    return img


def stream_from_camera():
    """Bat hinh tu webcam va gui xuong FPGA."""
    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("[WARN] Khong mo duoc webcam, chuyen sang test pattern.")
        return None
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, WIDTH)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, HEIGHT)
    return cap


def main():
    print("=== Stream to FPGA (UDP 100Mbps) ===")
    print(f"    Target : {FPGA_IP}:{FPGA_PORT}")
    print(f"    Reso   : {WIDTH}x{HEIGHT} Mono8")
    print(f"    FPS    : {TARGET_FPS}")
    print(f"    Packet : {2 + WIDTH} bytes/row x {HEIGHT} rows = {(2+WIDTH)*HEIGHT} bytes/frame")
    print()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 8 * 1024 * 1024)
    addr = (FPGA_IP, FPGA_PORT)

    # Thu mo webcam, neu khong duoc thi dung test pattern
    cap = stream_from_camera()
    use_camera = cap is not None
    if use_camera:
        print("[MODE] Webcam -> FPGA")
    else:
        print("[MODE] Test Pattern -> FPGA")

    frame_num = 0
    t0 = time.time()
    frame_interval = 1.0 / TARGET_FPS

    try:
        while True:
            t_start = time.time()

            # Lay anh
            if use_camera:
                ret, frame_bgr = cap.read()
                if not ret:
                    print("[WARN] Webcam mat ket noi, chuyen test pattern.")
                    cap.release()
                    cap = None
                    use_camera = False
                    continue
                # Chuyen sang grayscale va resize
                frame_gray = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2GRAY)
                img = cv2.resize(frame_gray, (WIDTH, HEIGHT))
            else:
                img = generate_test_pattern(frame_num)

            # Gui tung dong qua UDP
            for y in range(HEIGHT):
                header = struct.pack('>H', y)              # row_idx big-endian
                row_data = img[y, :].tobytes()              # 640 bytes Mono8
                sock.sendto(header + row_data, addr)

            # Hien thi preview tren PC
            cv2.imshow('Stream to FPGA (Press Q to quit)', img)
            if cv2.waitKey(1) & 0xFF == ord('q'):
                break

            # Thong ke FPS
            frame_num += 1
            if frame_num % TARGET_FPS == 0:
                elapsed = time.time() - t0
                fps = frame_num / elapsed
                bw_mbps = fps * HEIGHT * (2 + WIDTH) * 8 / 1e6
                print(f"[STATS] Frame #{frame_num}  FPS={fps:.1f}  BW={bw_mbps:.1f} Mbps")

            # Gioi han FPS
            elapsed_frame = time.time() - t_start
            sleep_time = frame_interval - elapsed_frame
            if sleep_time > 0:
                time.sleep(sleep_time)

    except KeyboardInterrupt:
        print("\n[INFO] Dung boi nguoi dung.")
    finally:
        if cap is not None:
            cap.release()
        cv2.destroyAllWindows()
        sock.close()
        print("[OK] Da don dep xong.")


if __name__ == "__main__":
    main()
