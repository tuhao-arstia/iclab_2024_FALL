# Lab03
- 練習寫pattern TAT
- spec沒有禁止 in_valid 和 out_valid 的重疊，導致FSM的設計不是很直觀
  
## 設計
1. tetris map多開三排的高度 (再省會加很多logic)
2. tetris map的更新 => 紀錄每個column最高點 + 比較放方塊後每個column最高點 來判斷方塊的正確放置位置
3. 每消一行 用 1 cycle來更新tetris map