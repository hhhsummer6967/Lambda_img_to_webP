#!/bin/bash

# 测试AWS CLI JSON参数格式

echo "测试环境变量JSON格式..."

# 正确的格式
ENV_JSON='{"WEBP_QUALITY":"85","OUTPUT_PREFIX":"","DELETE_ORIGINAL":"false"}'
echo "环境变量JSON: $ENV_JSON"

# 测试JSON是否有效
if echo "$ENV_JSON" | python3 -m json.tool > /dev/null 2>&1; then
    echo "✅ 环境变量JSON格式正确"
else
    echo "❌ 环境变量JSON格式错误"
fi

echo ""
echo "测试目标配置JSON格式..."

# 目标配置JSON
DEST_JSON='{"OnFailure":{"Destination":"arn:aws:sns:us-west-2:123456789012:test-topic"}}'
echo "目标配置JSON: $DEST_JSON"

# 测试JSON是否有效
if echo "$DEST_JSON" | python3 -m json.tool > /dev/null 2>&1; then
    echo "✅ 目标配置JSON格式正确"
else
    echo "❌ 目标配置JSON格式错误"
fi

echo ""
echo "完整的AWS CLI命令示例:"
echo "aws lambda create-function \\"
echo "  --function-name test-function \\"
echo "  --environment Variables='$ENV_JSON'"
echo ""
echo "aws lambda put-function-event-invoke-config \\"
echo "  --function-name test-function \\"
echo "  --destination-config '$DEST_JSON'"
