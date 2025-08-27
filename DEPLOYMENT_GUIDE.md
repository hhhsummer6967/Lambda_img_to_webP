# S3图片自动转WebP Lambda系统部署指南

## 📋 系统概述

本系统实现了S3桶中图片文件的自动WebP转换功能。当用户上传图片到指定S3桶时，系统会自动触发Lambda函数，将图片转换为WebP格式并保存到同一桶中。

### 🏗️ 架构组件

- **S3桶**: 存储原始图片和转换后的WebP文件
- **Lambda函数**: 执行图片格式转换
- **S3事件通知**: 自动触发Lambda函数
- **IAM角色**: 提供必要的权限
- **CloudWatch**: 记录执行日志
- **Pillow Layer**: 提供图片处理库

## 🚀 快速部署

### 前置条件

1. **AWS CLI**: 已安装并配置
2. **权限**: 具有以下服务的管理员权限
   - Lambda
   - S3
   - IAM
   - CloudWatch Logs
3. **环境**: bash shell环境

### 一键部署

```bash
# 克隆或下载项目文件
# 确保以下文件在同一目录：
# - deploy.sh
# - lambda_function.py
# - cleanup.sh
# - setup-s3-events.sh
# - create-lambda-package.sh

# 给脚本执行权限
chmod +x *.sh

# 执行部署（交互式）
./deploy.sh

# 或直接指定参数
./deploy.sh my-image-bucket us-west-2 image-to-webp
```

### 部署参数

| 参数 | 说明 | 默认值 | 示例 |
|------|------|--------|------|
| S3桶名 | 存储图片的桶名 | 必须提供 | `my-image-bucket` |
| AWS区域 | 部署区域 | `us-west-2` | `us-east-1` |
| 函数名 | Lambda函数名 | `image-to-webp` | `my-webp-converter` |

## 📝 手动部署步骤

如果需要手动部署或了解详细过程，请按以下步骤操作：

### 1. 创建IAM角色

```bash
# 创建信任策略
cat > trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# 创建IAM角色
aws iam create-role \
  --role-name image-to-webp-role \
  --assume-role-policy-document file://trust-policy.json

# 附加基础执行权限
aws iam attach-role-policy \
  --role-name image-to-webp-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
```

### 2. 创建S3访问策略

```bash
# 创建S3访问策略
cat > s3-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::YOUR-BUCKET-NAME/*"
    }
  ]
}
EOF

# 创建并附加策略
aws iam create-policy \
  --policy-name image-to-webp-s3-policy \
  --policy-document file://s3-policy.json

aws iam attach-role-policy \
  --role-name image-to-webp-role \
  --policy-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/image-to-webp-s3-policy
```

### 3. 创建Lambda函数

```bash
# 创建部署包
./create-lambda-package.sh

# 创建Lambda函数
aws lambda create-function \
  --function-name image-to-webp \
  --runtime python3.9 \
  --role arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/image-to-webp-role \
  --handler lambda_function.lambda_handler \
  --zip-file fileb://lambda_function.zip \
  --timeout 300 \
  --memory-size 512 \
  --layers arn:aws:lambda:REGION:770693421928:layer:Klayers-p39-pillow:1 \
  --environment Variables='{"WEBP_QUALITY":"85","OUTPUT_PREFIX":"","DELETE_ORIGINAL":"false"}'
```

### 4. 配置S3事件通知

```bash
# 使用专用脚本配置
./setup-s3-events.sh YOUR-BUCKET-NAME image-to-webp REGION
```

## ⚙️ 配置选项

### 环境变量

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `WEBP_QUALITY` | `85` | WebP质量 (1-100) |
| `OUTPUT_BUCKET` | 空 | 输出桶名（空则使用源桶） |
| `OUTPUT_PREFIX` | 空 | 输出前缀（空则在原目录） |
| `DELETE_ORIGINAL` | `false` | 是否删除原文件 |

### 修改配置示例

```bash
# 设置WebP质量为90%
aws lambda update-function-configuration \
  --function-name image-to-webp \
  --environment Variables='{"WEBP_QUALITY":"90","OUTPUT_PREFIX":"webp/","DELETE_ORIGINAL":"false"}'

# 增加内存和超时时间
aws lambda update-function-configuration \
  --function-name image-to-webp \
  --memory-size 1024 \
  --timeout 600
```

### 支持的图片格式

- **输入**: PNG, JPG, JPEG, BMP, TIFF, TIF
- **输出**: WebP
- **特性**: 支持透明通道、优化压缩

## 🧪 测试部署

### 1. 上传测试图片

```bash
# 上传单个图片
aws s3 cp test-image.png s3://your-bucket/

# 批量上传
aws s3 sync ./images/ s3://your-bucket/photos/
```

### 2. 检查转换结果

```bash
# 查看WebP文件
aws s3 ls s3://your-bucket/ --recursive | grep webp

# 查看文件元数据
aws s3api head-object --bucket your-bucket --key image.webp
```

### 3. 查看执行日志

```bash
# 实时查看日志
aws logs tail /aws/lambda/image-to-webp --follow

# 查看错误日志
aws logs filter-log-events \
  --log-group-name /aws/lambda/image-to-webp \
  --filter-pattern "ERROR"
```

## 📊 性能和成本

### 性能指标

- **处理时间**: 通常 < 2秒
- **压缩率**: 平均 60-80%
- **并发**: 支持1000个并发执行
- **文件大小**: 支持最大50MB图片

### 成本估算（每月1000张图片）

| 服务 | 成本 |
|------|------|
| Lambda执行 | ~$0.20 |
| S3存储 | 根据文件大小 |
| CloudWatch日志 | ~$0.50 |
| **总计** | **~$0.70** |

### 优化建议

| 图片大小 | 内存配置 | 超时设置 |
|----------|----------|----------|
| < 1MB | 512MB | 60秒 |
| 1-5MB | 1024MB | 180秒 |
| > 5MB | 2048MB | 300秒 |

## 📢 配置失败通知

为了及时发现和处理Lambda函数执行失败的情况，建议配置SNS通知：

### 自动通知配置脚本

创建一个自动配置脚本：

```bash
#!/bin/bash
# sns-notification-setup.sh

FUNCTION_NAME="image-to-webp"
REGION="us-west-2"
EMAIL="your-email@example.com"

# 创建SNS主题
echo "创建SNS主题..."
TOPIC_ARN=$(aws sns create-topic \
  --name lambda-image-conversion-failures \
  --region $REGION \
  --query 'TopicArn' --output text)

echo "SNS主题ARN: $TOPIC_ARN"

# 订阅邮件通知
echo "配置邮件订阅..."
aws sns subscribe \
  --topic-arn $TOPIC_ARN \
  --protocol email \
  --notification-endpoint $EMAIL \
  --region $REGION

# 配置Lambda失败目标
echo "配置Lambda失败通知..."
aws lambda put-function-event-invoke-config \
  --function-name $FUNCTION_NAME \
  --destination-config "{\"OnFailure\":{\"Destination\":\"$TOPIC_ARN\"}}" \
  --region $REGION

# 配置CloudWatch告警
echo "配置CloudWatch告警..."
aws cloudwatch put-metric-alarm \
  --alarm-name "lambda-image-conversion-errors" \
  --alarm-description "Lambda图片转换函数错误告警" \
  --metric-name Errors \
  --namespace AWS/Lambda \
  --statistic Sum \
  --period 300 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --dimensions Name=FunctionName,Value=$FUNCTION_NAME \
  --evaluation-periods 1 \
  --alarm-actions $TOPIC_ARN \
  --region $REGION

echo "✅ 通知配置完成！请检查邮箱确认订阅。"
```

### 手动配置步骤

#### 1. 创建SNS主题和订阅

```bash
# 创建主题
aws sns create-topic --name lambda-image-conversion-failures

# 获取主题ARN
TOPIC_ARN=$(aws sns list-topics --query 'Topics[?contains(TopicArn, `lambda-image-conversion-failures`)].TopicArn' --output text)

# 邮件订阅
aws sns subscribe \
  --topic-arn $TOPIC_ARN \
  --protocol email \
  --notification-endpoint your-email@example.com

# 短信订阅（可选）
aws sns subscribe \
  --topic-arn $TOPIC_ARN \
  --protocol sms \
  --notification-endpoint +1234567890
```

#### 2. 配置Lambda失败目标

```bash
aws lambda put-function-event-invoke-config \
  --function-name image-to-webp \
  --destination-config '{"OnFailure":{"Destination":"'$TOPIC_ARN'"}}'
```

#### 3. 设置CloudWatch告警

```bash
# 错误数量告警
aws cloudwatch put-metric-alarm \
  --alarm-name "lambda-image-conversion-errors" \
  --alarm-description "Lambda图片转换错误告警" \
  --metric-name Errors \
  --namespace AWS/Lambda \
  --statistic Sum \
  --period 300 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --dimensions Name=FunctionName,Value=image-to-webp \
  --evaluation-periods 1 \
  --alarm-actions $TOPIC_ARN

# 执行时间告警
aws cloudwatch put-metric-alarm \
  --alarm-name "lambda-image-conversion-duration" \
  --alarm-description "Lambda图片转换执行时间告警" \
  --metric-name Duration \
  --namespace AWS/Lambda \
  --statistic Average \
  --period 300 \
  --threshold 30000 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=FunctionName,Value=image-to-webp \
  --evaluation-periods 2 \
  --alarm-actions $TOPIC_ARN
```

### 通知消息示例

当Lambda函数失败时，你会收到类似以下的通知：

```json
{
  "version": "1.0",
  "timestamp": "2025-08-27T10:00:00.000Z",
  "requestContext": {
    "requestId": "12345678-1234-1234-1234-123456789012",
    "functionName": "image-to-webp",
    "condition": "RetriesExhausted",
    "approximateInvokeCount": 3
  },
  "requestPayload": {
    "Records": [...]
  },
  "responseContext": {
    "statusCode": 200,
    "executedVersion": "$LATEST"
  },
  "responsePayload": {
    "errorMessage": "图片转换失败: cannot identify image file",
    "errorType": "Exception"
  }
}
```

### 测试通知配置

```bash
# 测试失败通知
aws lambda invoke \
  --function-name image-to-webp \
  --payload '{"Records":[{"s3":{"bucket":{"name":"non-existent-bucket"},"object":{"key":"test.png"}}}]}' \
  response.json

# 检查响应
cat response.json
```

## 🛠️ 故障排除

### 常见问题

#### 1. Lambda函数未触发

**症状**: 上传图片后没有生成WebP文件

**排查步骤**:
```bash
# 检查S3事件配置
aws s3api get-bucket-notification-configuration --bucket your-bucket

# 检查Lambda权限
aws lambda get-policy --function-name image-to-webp

# 查看CloudWatch日志
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/image-to-webp"
```

**常见原因**:
- S3事件通知配置错误
- Lambda权限不足
- 文件格式不支持

#### 2. 图片转换失败

**症状**: Lambda执行但转换失败

**排查步骤**:
```bash
# 查看详细错误日志
aws logs filter-log-events \
  --log-group-name /aws/lambda/image-to-webp \
  --filter-pattern "ERROR"
```

**常见原因**:
- 图片文件损坏
- 内存不足
- 超时时间不够

#### 3. Pillow导入错误

**症状**: `cannot import name '_imaging' from 'PIL'`

**解决方案**:
```bash
# 确认使用正确的Layer
aws lambda update-function-configuration \
  --function-name image-to-webp \
  --layers arn:aws:lambda:REGION:770693421928:layer:Klayers-p39-pillow:1
```

### 调试工具

```bash
# 手动测试Lambda函数
aws lambda invoke \
  --function-name image-to-webp \
  --payload '{"Records":[{"s3":{"bucket":{"name":"test-bucket"},"object":{"key":"test.png"}}}]}' \
  response.json

# 查看函数配置
aws lambda get-function-configuration --function-name image-to-webp

# 监控执行指标
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Duration \
  --dimensions Name=FunctionName,Value=image-to-webp \
  --start-time 2025-08-27T00:00:00Z \
  --end-time 2025-08-27T23:59:59Z \
  --period 3600 \
  --statistics Average
```

## 🔄 更新和维护

### 更新Lambda代码

```bash
# 重新构建部署包
./create-lambda-package.sh

# 更新函数代码
aws lambda update-function-code \
  --function-name image-to-webp \
  --zip-file fileb://lambda_function.zip
```

### 更新S3事件配置

```bash
# 重新配置事件通知
./setup-s3-events.sh your-bucket image-to-webp us-west-2
```

### 版本管理

```bash
# 发布新版本
aws lambda publish-version --function-name image-to-webp

# 创建别名
aws lambda create-alias \
  --function-name image-to-webp \
  --name PROD \
  --function-version 1
```

## 🗑️ 清理资源

**⚠️ 重要安全提醒**: 为避免意外删除AWS资源，我们不提供自动清理脚本。

### 查看清理指南

请参考详细的手动清理指南：

```bash
cat CLEANUP_GUIDE.md
```

### 需要清理的主要资源

1. **Lambda函数**: `image-to-webp`
2. **IAM角色**: `image-to-webp-role`  
3. **IAM策略**: `image-to-webp-s3-policy`
4. **S3事件通知配置**
5. **CloudWatch日志组**: `/aws/lambda/image-to-webp`
6. **S3桶内容** (可选): 生成的WebP文件

### 清理原则

- 逐步手动删除，避免批量操作
- 先删除依赖资源，再删除主要资源
- 删除前确认资源不再需要
- 备份重要数据

## 📞 支持和资源

### 文档链接

- [AWS Lambda开发者指南](https://docs.aws.amazon.com/lambda/)
- [Amazon S3用户指南](https://docs.aws.amazon.com/s3/)
- [Pillow文档](https://pillow.readthedocs.io/)
- [WebP格式规范](https://developers.google.com/speed/webp)

### 社区资源

- [AWS Lambda Layers](https://github.com/keithrozario/Klayers)
- [AWS CLI参考](https://docs.aws.amazon.com/cli/)
- [CloudFormation模板](https://aws.amazon.com/cloudformation/templates/)

### 问题报告

如遇到问题，请提供以下信息：
- AWS区域
- Lambda函数名
- 错误日志
- 图片格式和大小
- 部署步骤

---

**版本**: v2.0  
**更新日期**: 2025-08-27  
**兼容性**: Python 3.9+, AWS CLI v2+
