# stream_gige_camera.py
# Mo ta: Stream GigE Camera (VimbaPython 1.2.1) den FPGA qua UDP 100Mbps
# Toi uu: Gop nhieu row vao 1 goi UDP de giam syscall overhead (480->8 goi/frame)
# Ngay: 16/05/2026
#
# Format goi UDP (moi goi = 1 chunk nhieu rows):
#   [frame_id: 2B big-endian] [start_row: 2B big-endian] [num_rows: 1B] [pixel_data: num_rows*WIDTH bytes]

import vimba
import socket
import struct
import time
import numpy as np
import cv2
import queue
import threading

# --- CONFIG ---
FPGA_IP    = "255.255.255.255"  # Broadcast; doi thanh IP cu the cua FPGA neu biet
FPGA_PORT  = 1234
WIDTH      = 640
HEIGHT     = 480
CAM_ID     = 'DEV_000F315CE51C'
ROWS_PER_CHUNK = 60             # 60 rows/goi => chi 8 goi UDP/frame (thay vi 480)
                                # 60 * 640 = 38400 bytes + 5 bytes header = 38405 bytes/goi
                                # Nam trong gioi han MTU an toan cua UDP (< 65507 bytes)

# Queue chuyen anh tu Callback thread sang Main thread (hien thi OpenCV)
frame_queue = queue.Queue(maxsize=2)

# Queue chuyen du lieu raw tu Callback sang TX thread (gui UDP)
tx_queue = queue.Queue(maxsize=4)


def tx_worker(sock, addr):
    """Luong rieng gui du lieu UDP, tranh block callback cua Vimba."""
    while True:
        item = tx_queue.get()
        if item is None:
            break  # Tin hieu ket thuc
        frame_id, img = item
        num_chunks = (HEIGHT + ROWS_PER_CHUNK - 1) // ROWS_PER_CHUNK
        for chunk_idx in range(num_chunks):
            row_start = chunk_idx * ROWS_PER_CHUNK
            row_end   = min(row_start + ROWS_PER_CHUNK, HEIGHT)
            num_rows  = row_end - row_start
            # Header: [frame_id 2B][start_row 2B][num_rows 1B]
            header = struct.pack('>HHB', frame_id, row_start, num_rows)
            pixel_data = img[row_start:row_end, :].tobytes()  # (num_rows, WIDTH) -> bytes
            sock.sendto(header + pixel_data, addr)
        tx_queue.task_done()


class FrameHandler:
    def __init__(self, sock, addr):
        self.sock        = sock
        self.addr        = addr
        self.frame_count = 0
        self.frame_id    = 0
        self.t0          = time.time()

    def __call__(self, cam, frame):
        if frame.get_status() == vimba.FrameStatus.Complete:
            # Lay raw ndarray tu Vimba
            raw = frame.as_numpy_ndarray()

            # --- Fix hien thi: Mono8 co the la (H, W) hoac (H, W, 1) ---
            if raw.ndim == 3:
                img = raw[:, :, 0]  # Squeeze channel cuoi
            else:
                img = raw           # Da la (H, W)

            # Crop/pad ve dung kich thuoc neu camera tra khac kich thuoc dat truoc
            img = img[:HEIGHT, :WIDTH]

            # GUI UDP (phi blocking - day vao TX queue)
            if not tx_queue.full():
                tx_queue.put_nowait((self.frame_id & 0xFFFF, img.copy()))

            # HIEN THI OpenCV (phi blocking - day vao display queue)
            if not frame_queue.full():
                frame_queue.put_nowait(img.copy())

            # CRITICAL FIX: Tra frame lai cho Vimba sau khi xu ly xong
            # Khong co lenh nay stream se dong cung sau khi het buffer
            cam.queue_frame(frame)

            # Thong ke FPS
            self.frame_count += 1
            self.frame_id    += 1
            now = time.time()
            if now - self.t0 >= 1.0:
                fps = self.frame_count / (now - self.t0)
                print(f"[STREAM] FPS: {fps:.1f}  |  Frame-ID: {self.frame_id}")
                self.frame_count = 0
                self.t0 = now


def main():
    print("=== GigE Legacy Stream (VimbaPython 1.2.1) ===")
    print(f"    Target : {FPGA_IP}:{FPGA_PORT}")
    print(f"    Reso   : {WIDTH}x{HEIGHT}")
    print(f"    Chunk  : {ROWS_PER_CHUNK} rows/packet  ({HEIGHT//ROWS_PER_CHUNK} packets/frame)")
    print(f"    MaxFPS : ~{100_000_000 // (HEIGHT//ROWS_PER_CHUNK * (5+ROWS_PER_CHUNK*WIDTH) * 8)} FPS (ly thuyet 100Mbps)")

    # Khoi tao socket UDP
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 16 * 1024 * 1024)  # 16MB send buffer
    addr = (FPGA_IP, FPGA_PORT)

    # Khoi dong TX thread
    tx_thread = threading.Thread(target=tx_worker, args=(sock, addr), daemon=True)
    tx_thread.start()

    with vimba.Vimba.get_instance() as vmb:
        cams = vmb.get_all_cameras()
        if not cams:
            print("[ERROR] Khong tim thay camera!")
            tx_queue.put(None)
            return

        # Tim dung cam theo ID, fallback ve cam[0]
        cam = cams[0]
        for c in cams:
            if c.get_id() == CAM_ID:
                cam = c
                break

        print(f"[INFO] Dang su dung camera: {cam.get_id()}")

        with cam:
            def set_feat(name, val):
                try:
                    cam.get_feature_by_name(name).set(val)
                except Exception as e:
                    print(f"  [WARN] Feature '{name}' = {val}: {e}")

            # Cau hinh camera
            set_feat('PixelFormat', 'Mono8')
            set_feat('Width', WIDTH)
            set_feat('Height', HEIGHT)
            set_feat('ExposureAuto', 'Off')
            set_feat('ExposureTimeAbs', 10000.0)
            set_feat('AcquisitionFrameRateAbs', 60.0)
            print("[OK] Camera da duoc cau hinh.")

            try:
                handler = FrameHandler(sock, addr)
                cam.start_streaming(handler, buffer_count=10)
                print("[RUNNING] Dang stream... Nhan 'q' trong cua so xem truoc de dung.")

                while True:
                    try:
                        img = frame_queue.get(timeout=0.1)
                        # Resize de hien thi (khong lam anh huong toi du lieu gui FPGA)
                        display = cv2.resize(img, (800, 600), interpolation=cv2.INTER_NEAREST)
                        cv2.imshow('GigE Camera -> FPGA (100Mbps)', display)
                    except queue.Empty:
                        pass

                    if cv2.waitKey(1) & 0xFF == ord('q'):
                        print("[INFO] Nguoi dung yeu cau dung.")
                        break

            except KeyboardInterrupt:
                print("\n[INFO] Bi ngat boi nguoi dung (Ctrl+C).")
            except Exception as e:
                print(f"\n[ERROR] Loi runtime: {e}")
            finally:
                cam.stop_streaming()
                tx_queue.put(None)  # Dung TX thread
                tx_thread.join(timeout=2)
                cv2.destroyAllWindows()
                sock.close()
                print("[OK] Da don dep xong.")


if __name__ == "__main__":
    main()
