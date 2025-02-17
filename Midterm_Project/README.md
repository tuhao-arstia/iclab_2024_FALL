# Midterm Project
- 感謝PH,HJ和YM貢獻的設計，壓縮資訊到SRAM中而避開DRAM的long access。
- 壓縮DRAM資訊的方法: classifier module
- dirty bit: output不變時直接避開access SRAM
- ================================================================
- 首次嘗試複數FSM寫法(Main, Focus_Sram, Expose_Sram, DRAM)，在控制上好寫非常多。
