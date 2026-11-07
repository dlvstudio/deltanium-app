# Phân tích: Contract hash dynamic (tránh fixed field list)

## Hiện trạng

### V1 (ký message)
- **Message** = format cố định: `TimeFixed|start|end|appPubKey|storagePubKey|totalFee|totalFileSize` (hoặc OpenEnded|...).
- **Vấn đề:** Thêm bất kỳ field mới (ví dụ `renewalOption`, `metadata`) → phải sửa format message → sửa App, Store, Blocker. Rất dễ vỡ.

### V2 (ký contract hash) hiện tại
- **Canonical** = danh sách **cố định** 11 field (appPublicKey, contractId, contractType, createdAtUnix, endDateUnix?, fileIds, startDateUnix, status, storageNodePublicKey, totalFee, totalFileSize).
- **Vấn đề:** Store trả thêm field mới (ví dụ `renewalOption`, `billingCycle`) → muốn field đó “có trong contract” khi ký thì phải thêm vào canonical ở **cả 3 nơi** (App, Store, Blocker). Code không “dynamic”.

---

## Mục tiêu

- Khi Store gửi thêm field mới cho App, **không phải** sửa nhiều chỗ (ít nhất là không phải sửa cả 3 codebase).
- V2 nên **ký trên “nội dung contract”** (tương đương JSON Store trả về), không build message từ danh sách field cố định như V1.

---

## Hướng 1: Store là nguồn chân lý — App chỉ ký hash Store gửi

**Ý tưởng:** Store tính `contractHash` từ contract (theo quy tắc Store muốn). Store trả về `contractHash` trong response (create / get / sign). App **không** tự build canonical, **không** tự tính hash; App chỉ ký chuỗi `contractHash` mà Store đã gửi.

**Luồng:**
1. App gọi create/sign → Store trả contract + `contractHash`.
2. App hiển thị contract cho user, user đồng ý.
3. App ký **đúng chuỗi** `contractHash` nhận từ Store → gửi `appSignature` (và có thể `signingVersion: 2`) lên Store.
4. Store đã có contract + contractHash; verify chữ ký App trên `contractHash` → coi như xong.
5. Khi submit tx lên Blocker, Store gửi contract + `contractHash` + chữ ký. Blocker chỉ cần verify chữ ký trên `contractHash` (đã làm).

**Khi Store thêm field mới:**
- Chỉ **Store** cần quyết định: field đó có nằm trong “canonical” để tính `contractHash` hay không.
- Nếu Store dùng **dynamic canonical** (xem Hướng 3) → chỉ cần đảm bảo object contract có field mới trước khi gọi `ComputeContractHash`; App và Blocker **không đổi code**.

**Ưu điểm:**
- Một nguồn chân lý: **Store** quyết định “contract là gì” và “hash để ký là gì”.
- App / Blocker không cần logic canonical, không cần danh sách field.
- Thêm field mới từ Store → tối đa chỉ sửa Store (và chỉ khi Store đổi cách tính hash).

**Nhược điểm:**
- App phải “tin” hash Store gửi (nhưng về mặt nghiệp vụ thì App đang ký đúng “bản contract Store đã mô tả”, nên chấp nhận được).

---

## Hướng 2: Canonical = “mọi field trừ danh sách loại trừ”

**Ý tưởng:** Không định nghĩa canonical bằng **danh sách field được phép**, mà bằng:
- Lấy toàn bộ contract (object) **trừ** một số key “chỉ dùng để chứng minh”, không coi là “nội dung contract”.
- Key loại trừ (exclusion list): `contractHash`, `messageToSign`, `appSignature`, `storageNodeSignature` (và có thể thêm sau nếu cần).
- Các key còn lại → sort alphabet → serialize giá trị theo quy ước chung → đó là canonical JSON.

**Quy ước giá trị (để hash giống nhau giữa App / Store / Blocker):**
- `totalFee` → luôn string F10 (đã có).
- `fileIds` → array string, sort alphabet.
- Số → number (integer nếu nguyên, không thêm .0 thừa).
- Các field “mới” chưa biết trước → serialize theo kiểu JSON chuẩn (string, number, bool, array, object). Chỉ cần 3 bên cùng một bộ quy tắc (ví dụ “number as number, string as string”) là hash khớp.

**Khi Store thêm field mới:**
- Field mới nằm trong object contract → **tự động** vào canonical (vì không nằm trong exclusion list).
- App / Store / Blocker đều dùng chung rule “all keys except X, sort, serialize” → không cần sửa danh sách field khi thêm field mới.

**Ưu điểm:**
- Dynamic thật: thêm field thì không phải sửa code (chỉ cần đảm bảo serialization nhất quán).
- Vẫn có thể verify hash trên Blocker (recompute từ contract nhận được) nếu muốn.

**Nhược điểm:**
- Cần implement đúng **cùng** quy tắc serial (số, chuỗi, mảng, object) ở 3 nơi; dễ lệch nếu có edge case (float, null, key order trong object lồng nhau).

---

## Hướng 3: Kết hợp — Store tính hash, Store dùng canonical dynamic

**Ý tưởng:** 
- **Store** là nơi duy nhất build canonical và tính `contractHash` (Hướng 1).
- Trong Store, canonical được build theo **quy tắc dynamic** (Hướng 2): “mọi field của contract trừ exclusion list, sort key, serialize chuẩn”.
- App chỉ ký `contractHash` do Store trả về; Blocker chỉ verify chữ ký trên `contractHash` trong tx.

**Kết quả:**
- Thêm field mới từ Store: chỉ cần đảm bảo object contract (trong Store) có field đó trước khi gọi hàm “canonical dynamic”. App và Blocker không đổi.
- Tránh hoàn toàn việc “build message từ danh sách field cố định” như V1.

---

## So sánh nhanh

| Tiêu chí | V1 (message) | V2 hiện tại (fixed list) | Hướng 1 (Store hash) | Hướng 2 (dynamic canonical) | Hướng 3 (1+2) |
|----------|----------------|---------------------------|----------------------|-----------------------------|----------------|
| Thêm field mới | Sửa 3 chỗ, đổi format | Sửa 3 chỗ, thêm vào list | Chỉ sửa Store (nếu cần) | Không sửa (auto include) | Chỉ sửa Store (nếu cần) |
| App build canonical? | Không (build message) | Có, 11 field cố định | **Không** | Có, rule “all except X” | **Không** |
| Nguồn chân lý | Không rõ (cùng format) | Không rõ (cùng list) | **Store** | Cùng rule 3 bên | **Store** |
| Độ phức tạch App | Trung bình | Cao (sync list với Store) | **Thấp** (chỉ ký hash) | Cao (serial rule) | **Thấp** |

---

## Đề xuất

- **Ngắn hạn / ít thay đổi:** Giữ luồng V2 hiện tại nhưng **chính thức hóa Hướng 1**: App **luôn** dùng `contractHash` do Store trả về để ký (không tự tính hash từ model). Store đã trả `contractHash` trong sign response; có thể thêm vào create response nếu App cần ký ngay sau create. Blocker đã chỉ verify chữ ký trên `contractHash` → không cần recompute hash. Như vậy đã “ký trên thứ Store gửi” (hash của contract do Store mô tả).
- **Dài hạn / dynamic thật:** Store chuyển sang **canonical dynamic** (Hướng 3): hàm ComputeContractHash trên Store không dùng danh sách 11 field cố định, mà build từ toàn bộ contract (object) trừ exclusion list, sort key, serialize chuẩn. Khi đó thêm field mới từ Store không đòi hỏi thay đổi App hay Blocker; chỉ cần Store đảm bảo object contract có field mới trước khi tính hash.

Tóm lại: **Đã đảm bảo “dynamic” theo nghĩa “không phụ thuộc fixed message như V1”** nếu ta áp dụng Hướng 1 (App chỉ ký hash Store gửi). **Đảm bảo “field mới từ Store không đòi hỏi sửa code”** nếu Store dùng canonical dynamic (Hướng 3).
