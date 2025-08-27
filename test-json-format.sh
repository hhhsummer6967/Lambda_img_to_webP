#!/bin/bash

# 测试AWS CLI参数格式

echo "测试AWS CLI环境变量格式..."

# AWS CLI环境变量的正确格式（键值对格式）
ENV_FORMAT='{WEBP_QUALITY=85,OUTPUT_PREFIX="",DELETE_ORIGINAL=false}'
echo "环境变量格式: Variables='$ENV_FORMAT'"

echo ""
echo "测试目标配置JSON格式..."

# 目标配置JSON（这个仍然使用JSON格式）
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
echo "# 创建函数"
echo "aws lambda create-function \\"
echo "  --function-name test-function \\"
echo "  --environment Variables='$ENV_FORMAT'"
echo ""
echo "# 配置失败通知"
echo "aws lambda put-function-event-invoke-config \\"
echo "  --function-name test-function \\"
echo "  --destination-config '$DEST_JSON'"
echo ""
echo "# 更新环境变量"
echo "aws lambda update-function-configuration \\"
echo "  --function-name test-function \\"
echo "  --environment Variables='{WEBP_QUALITY=90}'"
