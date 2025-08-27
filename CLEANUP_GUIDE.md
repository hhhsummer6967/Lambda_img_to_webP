# 资源清理指南

## ⚠️ 重要提醒

**请谨慎操作！** 删除AWS资源是不可逆的操作。建议在清理前：
1. 确认不再需要这些资源
2. 备份重要数据
3. 逐步手动删除，避免误操作

## 📋 需要清理的资源列表

本系统部署后会创建以下AWS资源：

### 1. Lambda函数
- **资源名称**: `image-to-webp` (或你指定的函数名)
- **资源类型**: AWS Lambda Function
- **说明**: 执行图片转换的核心函数

### 2. IAM角色
- **资源名称**: `image-to-webp-role` (或 `{函数名}-role`)
- **资源类型**: IAM Role
- **说明**: Lambda函数的执行角色

### 3. IAM策略
- **资源名称**: `image-to-webp-s3-policy` (或 `{函数名}-s3-policy`)
- **资源类型**: IAM Policy
- **说明**: 允许Lambda访问S3桶的自定义策略

### 4. S3事件通知配置
- **资源位置**: 在你的S3桶中
- **资源类型**: S3 Bucket Notification Configuration
- **说明**: 触发Lambda函数的事件配置

### 5. CloudWatch日志组
- **资源名称**: `/aws/lambda/image-to-webp` (或 `/aws/lambda/{函数名}`)
- **资源类型**: CloudWatch Log Group
- **说明**: 存储Lambda函数执行日志

### 6. S3桶内容 (可选清理)
- **资源位置**: 你的S3桶中的WebP文件
- **资源类型**: S3 Objects
- **说明**: 系统生成的WebP格式图片文件

## 🗑️ 手动清理步骤

### 步骤1: 清除S3事件通知配置

```bash
# 查看当前配置
aws s3api get-bucket-notification-configuration --bucket YOUR-BUCKET-NAME

# 清空事件通知配置
aws s3api put-bucket-notification-configuration \
  --bucket YOUR-BUCKET-NAME \
  --notification-configuration '{}'
```

### 步骤2: 删除Lambda函数

```bash
# 查看函数信息
aws lambda get-function --function-name image-to-webp

# 删除Lambda函数
aws lambda delete-function --function-name image-to-webp
```

### 步骤3: 删除CloudWatch日志组

```bash
# 查看日志组
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/image-to-webp"

# 删除日志组
aws logs delete-log-group --log-group-name "/aws/lambda/image-to-webp"
```

### 步骤4: 清理IAM资源

```bash
# 获取账户ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# 分离自定义策略
aws iam detach-role-policy \
  --role-name image-to-webp-role \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/image-to-webp-s3-policy

# 分离AWS托管策略
aws iam detach-role-policy \
  --role-name image-to-webp-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

# 删除自定义策略
aws iam delete-policy \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/image-to-webp-s3-policy

# 删除IAM角色
aws iam delete-role --role-name image-to-webp-role
```

### 步骤5: 清理S3桶内容 (可选)

⚠️ **注意**: 只删除系统生成的WebP文件，不要删除原始图片

```bash
# 列出WebP文件
aws s3 ls s3://YOUR-BUCKET-NAME --recursive | grep "\.webp$"

# 删除特定WebP文件
aws s3 rm s3://YOUR-BUCKET-NAME/path/to/file.webp

# 批量删除WebP文件 (谨慎使用)
aws s3 rm s3://YOUR-BUCKET-NAME --recursive --exclude "*" --include "*.webp"
```

## 🔍 验证清理结果

### 检查Lambda函数是否已删除
```bash
aws lambda get-function --function-name image-to-webp
# 应该返回错误: ResourceNotFoundException
```

### 检查IAM资源是否已删除
```bash
aws iam get-role --role-name image-to-webp-role
# 应该返回错误: NoSuchEntity

aws iam get-policy --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/image-to-webp-s3-policy
# 应该返回错误: NoSuchEntity
```

### 检查S3事件通知是否已清除
```bash
aws s3api get-bucket-notification-configuration --bucket YOUR-BUCKET-NAME
# 应该返回空的配置: {}
```

### 检查CloudWatch日志组是否已删除
```bash
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/image-to-webp"
# 应该返回空的logGroups数组
```

## 💰 成本影响

清理这些资源后，将停止产生以下费用：
- Lambda函数执行费用
- CloudWatch日志存储费用
- S3事件通知费用 (通常很少)

**注意**: S3桶本身和其中的文件存储费用不受影响，除非你选择删除WebP文件。

## 🚨 故障排除

### 如果删除IAM角色时出错
可能是因为角色仍然被其他资源使用，请确保：
1. Lambda函数已完全删除
2. 所有策略已分离
3. 等待几分钟后重试

### 如果删除策略时出错
可能是因为策略仍然附加到其他角色，请：
1. 检查策略的附加情况
2. 分离所有附加的角色
3. 然后删除策略

### 如果S3事件通知清除失败
可能是权限问题，请确保：
1. 有S3桶的管理权限
2. 桶名称正确
3. 区域设置正确

## 📞 需要帮助？

如果在清理过程中遇到问题：
1. 检查AWS CLI配置和权限
2. 查看AWS控制台确认资源状态
3. 参考AWS官方文档
4. 联系AWS支持 (付费用户)

---

**重要提醒**: 删除操作无法撤销，请在执行前仔细确认！
