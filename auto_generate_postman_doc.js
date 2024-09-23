if (pm.collectionVariables.get('generate-doc') != 1) {
    return;
}
// 获取当前请求的 requestId
const requestId = pm.info.requestId;
// 你的 Postman Collection UID
const collectionId = '32187319-8d293f57-55ac-4add-8d78-32d6f7f83cd8';
// 你的 postman api key
const postmanApiKey = pm.collectionVariables.get('postman-api-key');
// 获取当前 API 响应
const responseBody = pm.response.json();
// 获取请求路径，转换成描述名称
commonDesc = '';
pm.request.url.path.forEach((pathItem) => {
    commonDesc += firstUpperCase(pathItem);
});

// 组装新的文档内容
let newDocumentation = '';

// 获取uri
uriParamsStr = '';
const queryParams = pm.request.url.query.all();
if (queryParams.length > 0) {
    queryParams.forEach((param) => {
        uriParamsStr += ('|' + param.key + '|string|Y| |' + param.value + '|\n');
    });
    uriParamsStr = `\n### Params_${commonDesc}\n\n|字段名|类型|是否必填|说明|示例|\n|---|---|---|---|---|\n${uriParamsStr}`;
}
// 获取body
bodyParamsStr = '';
if (pm.request.body.mode === 'urlencoded' || pm.request.body.mode === 'formdata') {
    const requestBody = pm.request.body[pm.request.body.mode].members;
    if (requestBody.length > 0) {
        requestBody.forEach((param) => {
            bodyParamsStr += ('|' + param.key + '|string|Y| |' + param.value + '|\n');
        });
        bodyParamsStr = `\n### Params_${commonDesc}\n\n|字段名|类型|是否必填|说明|示例|\n|---|---|---|---|---|\n${bodyParamsStr}`;
    }
}
// 获取json
jsonParamsStr = '';
if (pm.request.body.mode === 'raw') {
    const rawBody = pm.request.body.raw;
    try {
        const jsonBody = JSON.parse(rawBody);
        jsonParamsStr = generateJsonMd(jsonBody, commonDesc);
    } catch (e) {
        console.log('Body is not in JSON format');
        return;
    }
}

if (uriParamsStr != '' || bodyParamsStr != '' || jsonParamsStr != '') {
    newDocumentation += '## 入参定义 \n';
}
newDocumentation += uriParamsStr;
newDocumentation += bodyParamsStr;
newDocumentation += jsonParamsStr;

// 解析响应结果
if (responseBody['status_code'] == undefined && responseBody['message'] == undefined) {
    newDocumentation += '\n ## 出参定义 ';
    newDocumentation += generateJsonMd(responseBody, commonDesc, 'Response_');
}

// 准备更新 Collection 的 API 请求
pm.sendRequest({
    url: `https://api.getpostman.com/collections/${collectionId}`,
    method: 'GET',
    header: {
        'X-Api-Key': postmanApiKey
    }
}, function (err, res) {
    if (err) {
        console.log('Error retrieving collection:', err);
        return;
    }
    const collection = res.json();
    const requests = collection.collection.item;
    let requestUpdated = false;
    function findAndUpdateRequest(items) {
        items.forEach((item) => {
            if (item.item) {
                findAndUpdateRequest(item.item);
            } else if (item.id === requestId) {
                item.request.description = newDocumentation;
                requestUpdated = true;
            }
        });
    }
    findAndUpdateRequest(requests);

    if (!requestUpdated) {
        console.log('No matching request ID found.');
        return;
    }
    
    // 发送 PUT 请求更新集合
    pm.sendRequest({
        url: `https://api.getpostman.com/collections/${collectionId}`,
        method: 'PUT',
        header: {
            'Content-Type': 'application/json',
            'X-Api-Key': postmanApiKey
        },
        body: {
            mode: 'raw',
            raw: JSON.stringify(collection)
        }
    }, function (err, res) {
        if (err) {
            console.log('Error updating collection:', err);
        } else {
            console.log('Documentation updated successfully.');
        }
    });
});

function firstUpperCase(field)
{
    return field.substr(0, 1).toUpperCase() + field.substr(1)
}

function underlineToCamelCase(field)
{
    fieldStr = '';
    field.split('_').forEach((item) => {
        fieldStr += firstUpperCase(item);
    });
    return fieldStr;
}

function getBooleanValue(value) {
    return value ? "true" : "false";
}

function generateJsonMd(json, name, prefix = '')
{
    let output = '';
    if (typeof json === 'object' && !Array.isArray(json) && json !== null) {
        output += generateObjectMd(json, 'Obj_' + name, prefix);
    } else if (Array.isArray(json)) {
        output += generateArrayMd(json, 'List_' + name, prefix);
    }
    return output;
}

// 解析json里的object
function generateObjectMd(json, name, prefix = '') {
    let output = '\n<a id="' + prefix + name + '"></a>\n### ' + prefix + name + '\n\n| 参数名 | 类型 | 必填 | 描述 | 示例 |\n|---|---|---|---|---|\n';
    let subOutput = '';
    Object.keys(json).forEach(key => {
        const value = json[key];
        const valueType = typeof value;
        if (valueType === 'object' && !Array.isArray(value) && value !== null) {
            const nestedName = `Obj_${underlineToCamelCase(key)}`;
            output += `|${key}|[${prefix + nestedName}](#${prefix + nestedName})|Y| | |\n`;
            subOutput += generateObjectMd(value, nestedName, prefix);
        } else if (Array.isArray(value)) {
            listName = `List_${underlineToCamelCase(key)}`;
            output += `|${key}|[${prefix + listName}](#${prefix + listName})|Y| | |\n`;
            subOutput += generateArrayMd(value, listName, prefix);
        } else if (valueType === 'string') {
            output += `|${key}|string|Y| |${value}|\n`;
        } else if (valueType === 'number') {
            output += `|${key}|number|Y| |${value}|\n`;
        } else if (valueType === 'boolean') {
            output += `|${key}|boolean|Y| |${getBooleanValue(value)}|\n`;
        } else if (value === null) {
            output += `|${key}|string|N| |null|\n`;
        } else {
            output += `|${key}|unkown|N| |null|\n`;
        }
    });

    return output + subOutput;
}

// 解析数组
function generateArrayMd(json, listName = '', prefix = '')
{
    let output = '\n<a id="' + prefix + listName + '"></a>\n### ' + prefix + listName + '\n\n| 参数名 | 类型 | 必填 | 描述 | 示例 |\n|---|---|---|---|---|\n';
    let subOutput = '';
    if (json === 'undefined') {
        output += `| |List(unkown)|N| |null|\n`;
        return output;
    }

    const value = json[0];
    const valueType = typeof value;
    if (valueType === 'object' && !Array.isArray(value) && value !== null) {
        objName = 'Obj_' + listName + '_Item';
        output += `| |[List(${prefix + objName})](#${prefix + objName})|Y| | |\n`
        subOutput += generateObjectMd(value, objName, prefix);
    } else if (Array.isArray(value)) {
        output += `| |[List(${prefix + listName})](#${prefix + listName})|Y| | |\n`
        subOutput += generateArrayMd(value[0], listName, prefix);
    } else if (valueType === 'string') {
            output += `| |List(string)|Y| |${value}|\n`;
    } else if (valueType === 'number') {
        output += `| |List(number)|Y| |${value}|\n`;
    } else if (valueType === 'boolean') {
        output += `| |List(boolean)|Y| |${getBooleanValue(value)}|\n`;
    } else if (value === null) {
        output += `| |List(string)|N| |null|\n`;
    } else {
        output += `| |List(unkown)|N| |null|\n`;
    }

    return output + subOutput;
}


