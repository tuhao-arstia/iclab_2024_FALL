# Lab04
- My Code Review https://www.youtube.com/watch?v=3v65DoTsjZY
- 學習pipeline設計來增加throughput
- 學習共用module來節省硬體總量和面積
- 學習call IP
- 我使用cycle-based設計 (counter)
## tips
- 想清楚硬體要開多少以及data flow，再開始寫設計
- 沒有power限制的情況下，shift register非常好用，可以減少combinational logic面積
- 受制於題目，systolic array的設計沒有取得更好的performance，但systolic array是個好東西