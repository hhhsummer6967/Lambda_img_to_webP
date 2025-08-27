#!/bin/bash

# Lambda部署包构建脚本
# 用于创建不包含依赖的轻量级Lambda部署包
# 依赖通过AWS公共Layer提供

set -e

echo "🔨 开始构建Lambda部署包..."

# 清理之前的构建
rm -rf lambda_package
rm -f lambda_function.zip

# 检查必需文件
if [ ! -f "lambda_function.py" ]; then
    echo "❌ 错误: lambda_function.py 文件不存在"
    echo "请确保 lambda_function.py 文件在当前目录"
    exit 1
fi

# 创建构建目录
mkdir -p lambda_package

# 复制Lambda函数代码
echo "📁 复制Lambda函数代码..."
cp lambda_function.py lambda_package/

# 创建部署包
echo "📦 创建部署包..."
cd lambda_package
zip -r ../lambda_function.zip .
cd ..

# 显示包大小
echo "✅ 部署包创建完成！"
ls -lh lambda_function.zip

# 检查包大小（Lambda限制50MB）
if command -v stat >/dev/null 2>&1; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        PACKAGE_SIZE=$(stat -f%z lambda_function.zip)
    else
        # Linux
        PACKAGE_SIZE=$(stat -c%s lambda_function.zip)
    fi
    PACKAGE_SIZE_KB=$((PACKAGE_SIZE / 1024))
    
    echo "📊 包大小: ${PACKAGE_SIZE_KB}KB"
    
    if [ $PACKAGE_SIZE_KB -gt 51200 ]; then  # 50MB = 51200KB
        echo "⚠️  警告: 部署包大小超过50MB"
    else
        echo "✅ 部署包大小符合要求"
    fi
fi

echo ""
echo "📋 部署包已创建: lambda_function.zip"
echo ""
echo "🚀 下一步:"
echo "1. 使用部署脚本: ./deploy.sh"
echo "2. 或手动部署:"
echo "   aws lambda create-function --function-name image-to-webp \\"
echo "     --runtime python3.9 --role arn:aws:iam::ACCOUNT:role/lambda-role \\"
echo "     --handler lambda_function.lambda_handler \\"
echo "     --zip-file fileb://lambda_function.zip \\"
echo "     --timeout 300 --memory-size 512 \\"
echo "     --layers arn:aws:lambda:REGION:770693421928:layer:Klayers-p39-pillow:1"
echo ""
echo "💡 提示: 本包不包含Pillow依赖，需要使用AWS公共Layer"
