# Access to TOU

แปลง Access datalog เป็นไฟล์ TOU รายเดือนสำหรับ Dashboard_TOU

[ทดลองหน้าเว็บด้วยข้อมูลจำลอง](https://satitpae.github.io/Access-to-TOU/)

## ใช้กับไฟล์จริงบน Windows

1. ใช้ PowerShell 7 และ Microsoft Access Database Engine ที่มี bitness ตรงกัน
2. กด **Code → Download ZIP** แล้วแตกไฟล์
3. ดับเบิลคลิก `Open-AccessToTOU.cmd` แล้วเลือก `.mdb` หรือ `.accdb`
4. ติ๊กเดือนในหน้าเว็บ กด **Export .tou** แล้วดาวน์โหลด

อ่านตาราง `Data Log # 1` และดึงรหัสฐาน 16 จากต้นชื่อไฟล์ เช่น `D18_` เพื่อสร้างชื่อ `D18Nov26.tou` การแปลงไฟล์จริงทำบนเครื่อง หน้า HTML ชั่วคราวมีข้อมูลที่ใช้สร้างไฟล์ดาวน์โหลด
