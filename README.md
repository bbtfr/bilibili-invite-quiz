嗶哩嗶哩 激活问题补完计划
===

目标
---
此项目目标是建立完整的bilibili新手激活问题集，并采用神经网络算法配合统计方法和人肉识别，建立答案库

已解决问题
---
* 一个激活问题抓取爬虫（Ruby脚本）
* 一个激活问题集（考虑到便于查阅，使用YAML格式）
* 一个激活问题集转网页的脚本，用于展示题目，收集志愿者人肉识别的结果

TODO
---
* 计划使用 React 或 Backbone 重写Web端
* 数据储存迁移到 LeanCloud 上
* 激活问题爬虫加入随机答题，抓取得分的功能
* 一个激活答案集
* 由于新手问题答题的种种限制，考虑编写一个bilibili注册机

Usage
---
```shell
git clone git@github.com:bbtfr/bilibili-invite-quiz.git && cd bilibili-invite-quiz

# Add your bilibili cookie string to db/auth_cookies.yml
ruby bin/thor.rb grab

```
