# S3图片自动转WebP Lambda系统

## 📋 概述

这是一个基于AWS Lambda的智能图片转换系统，当图片上传到S3桶时自动触发转换为WebP格式。系统支持多种图片格式，提供高压缩率和详细的转换日志。

## 🏗️ 系统架构

```
S3上传图片 → S3事件通知 → Lambda函数 → WebP转换 → S3存储
     ↓              ↓           ↓         ↓         ↓
   原始图片      自动触发    图片处理   格式转换   结果保存
```

### 核心组件
- **Lambda函数**: 图片格式转换处理
- **S3事件通知**: 自动触发机制
- **Pillow Layer**: 图片处理库
- **CloudWatch**: 日志监控

## 📦 项目文件结构

```
s3-image-to-webp/
├── README.md                           # 本文档
├── lambda_function.py                  # Lambda函数代码
├── requirements.txt                    # Python依赖
├── deploy.sh                          # 一键部署脚本
├── create-lambda-package.sh           # Lambda包构建脚本
├── setup-s3-events.sh                # S3事件配置脚本
└── CLEANUP_GUIDE.md                   # 资源清理指南
```

## 🚀 快速部署

### 前置要求
- AWS CLI 已配置并有管理员权限
- bash shell环境
- 已有S3桶或创建新桶

### 一键部署命令

```bash
# 基本部署（会提示输入参数）
./deploy.sh

# 直接指定参数部署
./deploy.sh my-image-bucket us-west-2 image-to-webp-function
```

### 部署参数说明

| 参数 | 说明 | 默认值 |
|------|------|--------|
| S3桶名 | 存储图片的S3桶 | 必须提供 |
| AWS区域 | 部署区域 | us-west-2 |
| 函数名 | Lambda函数名称 | image-to-webp |

## ⚙️ 支持的图片格式

- **输入格式**: JPG, JPEG, PNG, BMP, TIFF, TIF
- **输出格式**: WebP
- **压缩质量**: 85%（可配置）

## 🎯 使用方法

### 1. 上传图片文件

```bash
# 上传单个图片
aws s3 cp image.png s3://your-bucket/

# 上传多个图片
aws s3 sync ./images/ s3://your-bucket/photos/
```

### 2. 自动转换

系统会自动：
- 检测上传的图片格式
- 转换为WebP格式
- 保存在相同目录
- 记录转换信息

### 3. 查看结果

```bash
# 查看转换后的文件
aws s3 ls s3://your-bucket/ --recursive | grep webp

# 查看文件元数据
aws s3api head-object --bucket your-bucket --key image.webp
```

## 📊 转换效果示例

| 原始格式 | 原始大小 | WebP大小 | 压缩率 |
|----------|----------|----------|--------|
| PNG | 516 KB | 160 KB | 69.0% |
| JPG | 2.1 MB | 890 KB | 57.6% |
| BMP | 5.2 MB | 1.2 MB | 76.9% |

## 🔧 环境变量配置

在Lambda函数中可配置以下环境变量：

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `WEBP_QUALITY` | `85` | WebP质量 (1-100) |
| `OUTPUT_BUCKET` | 空 | 输出桶名（空则使用源桶） |
| `OUTPUT_PREFIX` | 空 | 输出前缀（空则在原目录） |
| `DELETE_ORIGINAL` | `false` | 是否删除原文件 |

### 配置示例

```bash
# 设置WebP质量为90%
aws lambda update-function-configuration \
  --function-name image-to-webp \
  --environment Variables='{
    "WEBP_QUALITY":"90",
    "DELETE_ORIGINAL":"false"
  }'
```

## 📈 监控和日志

### 查看执行日志
```bash
# 实时查看日志
aws logs tail /aws/lambda/image-to-webp --follow

# 查看错误日志
aws logs filter-log-events \
  --log-group-name /aws/lambda/image-to-webp \
  --filter-pattern "ERROR"
```

### 监控指标
- Lambda执行次数和持续时间
- 成功/失败转换率
- 内存使用情况
- 错误类型统计

## 🛠️ 故障排除

### 常见问题

#### 1. Lambda函数未触发
```bash
# 检查S3事件配置
aws s3api get-bucket-notification-configuration --bucket your-bucket

# 检查Lambda权限
aws lambda get-policy --function-name image-to-webp
```

#### 2. 图片转换失败
- 检查文件是否为有效图片格式
- 查看CloudWatch日志获取详细错误信息
- 确认Lambda内存和超时配置

#### 3. 权限错误
```bash
# 检查IAM角色权限
aws iam get-role --role-name lambda-execution-role
aws iam list-attached-role-policies --role-name lambda-execution-role
```

### 调试命令
```bash
# 手动测试Lambda函数
aws lambda invoke \
  --function-name image-to-webp \
  --payload file://test-event.json \
  response.json

# 查看函数配置
aws lambda get-function-configuration --function-name image-to-webp
```

## 🔄 更新和维护

### 更新Lambda代码
```bash
# 重新构建并部署
./create-lambda-package.sh
aws lambda update-function-code \
  --function-name image-to-webp \
  --zip-file fileb://lambda-function.zip
```

### 更新配置
```bash
# 增加内存
aws lambda update-function-configuration \
  --function-name image-to-webp \
  --memory-size 1024

# 增加超时时间
aws lambda update-function-configuration \
  --function-name image-to-webp \
  --timeout 600
```

## 💰 成本优化

### 建议配置
- **小图片 (< 1MB)**: 512MB内存，60秒超时
- **中等图片 (1-5MB)**: 1024MB内存，180秒超时  
- **大图片 (> 5MB)**: 2048MB内存，300秒超时

### 成本估算
基于每月处理1000张图片：
- Lambda执行费用: ~$0.20
- S3存储费用: 根据文件大小
- CloudWatch日志: ~$0.50

## 🗑️ 清理资源

**重要**: 为了避免意外删除AWS资源，请参考详细的清理指南：

```bash
# 查看清理指南
cat CLEANUP_GUIDE.md
```

清理指南包含：
- 需要清理的资源列表
- 逐步手动清理说明
- 验证清理结果的方法
- 故障排除建议

## 📝 版本信息

- **版本**: v2.0
- **最后更新**: 2025-08-27
- **支持的AWS区域**: 全部区域
- **Python版本**: 3.9+
- **依赖库**: Pillow (通过AWS Layer)

## 🤝 贡献指南

1. Fork本项目
2. 创建功能分支
3. 提交更改
4. 创建Pull Request

## 📞 支持

### 问题报告
- GitHub Issues
- AWS Support (付费用户)

### 有用链接
- [AWS Lambda文档](https://docs.aws.amazon.com/lambda/)
- [Pillow文档](https://pillow.readthedocs.io/)
- [WebP格式说明](https://developers.google.com/speed/webp)

---

**注意**: 本系统使用AWS公共Layer提供Pillow库支持，确保在支持的区域部署。首次部署可能需要几分钟时间来下载和配置依赖。
