# 从ERROR_code.md提取错误码
lines = open('ERROR_CODE.md','r',encoding='utf-8').readlines()
target_line = 0
total = len(lines)
for index, line in enumerate(lines):
    if 'Code' in line:
        target_line = index + 2
        break

mapping = dict()
for index in range(target_line, total):
    _,code,cn,en,_ = lines[index].replace(' ','').strip().split('|')
    if code in mapping:
        print(f"{code=} duplicated")
        exit(-1)
    mapping[code] = (cn, en,)


写一个pre-commit来检查提交内容
1、检查ERROR_CODE.md里面有没有重复的错误码，如果有，则不允许提交且给出提示
2、检查ERROR_CODE.md有没有变动，如果有则调用confluence接口，获取在线错误码数据，如果没有，则允许提交
3、检查ERROR_CODE.md的改动与confluence上面的有没有冲突，如果ERROR_CODE.md新增的错误码在在线错误码数据中已存在，则不允许提交并给出提示
4、把ERROR_CODE.md里面的所有错误码更新到confluence文档里面
5、要注意多人协作可能会产生的问题，不要误覆盖confluence文档，导致错误码丢失、重复、本该删除的未删除等问题