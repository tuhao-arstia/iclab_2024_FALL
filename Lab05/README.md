# Lab05
- 練習使用Memory Compiler捏SRAM module
- SRAM就是smaller area but slower access的register
- 不同的action推薦個別寫一個module出來
- 設計方向:
  
  1. 主要目標是不要再開一堆register來存資料，所以課題是如何減少access SRAM的cycle penalty
   - 捏出來的SRAM一次讀寫量為 2 words，減少access所需的cycle數以及完成action需要的cycle數，但也導致combinational logic 容易出錯(8000行中佔了約6000行)
   - 考慮action對輸出是否有影響，重排action (最少化SRAM讀寫的次數)
## tips
- SRAM read data時的delay會是設計時的一大障礙，寫過這次lab就會比較懂的控制怎麼寫
- SRAM module每個腳位一定要宣告清楚 .port_name(port_connection)，會導致RTL Simulation能過但是Gate Simulation永遠過不了 (2de敗筆)
- 盡量不要設計一個global counter給整個電路用，fanout有可能會炸開，多用用local counter
## 小小心聲
- 如果只是要了解SRAM運作，比較推薦寫register版本，不用想東想西的。
- SRAM有自己的FSM可能會更好控制﹑