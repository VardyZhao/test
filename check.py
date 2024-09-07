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
