import json
import boto3
import os
from PIL import Image
import io
import traceback
from urllib.parse import unquote_plus

# 初始化S3客户端
s3_client = boto3.client('s3')

def lambda_handler(event, context):
    """
    S3事件触发的Lambda函数，自动将上传的图片转换为WebP格式
    """
    
    # 支持的图片格式
    SUPPORTED_FORMATS = {'.jpg', '.jpeg', '.png', '.bmp', '.tiff', '.tif'}
    
    # WebP质量设置（可通过环境变量配置）
    WEBP_QUALITY = int(os.environ.get('WEBP_QUALITY', '85'))
    
    # 输出桶名（可通过环境变量配置，默认使用源桶）
    OUTPUT_BUCKET = os.environ.get('OUTPUT_BUCKET', '')
    
    # 输出前缀（默认为空，即在原文件目录）
    OUTPUT_PREFIX = os.environ.get('OUTPUT_PREFIX', '')
    
    processed_files = []
    failed_files = []
    
    try:
        # 处理S3事件中的每个记录
        for record in event['Records']:
            # 获取桶名和对象键
            bucket_name = record['s3']['bucket']['name']
            object_key = unquote_plus(record['s3']['object']['key'])
            
            print(f"开始处理文件: s3://{bucket_name}/{object_key}")
            
            try:
                # 检查文件扩展名
                file_extension = os.path.splitext(object_key)[1].lower()
                if file_extension not in SUPPORTED_FORMATS:
                    print(f"跳过不支持的文件格式: {file_extension}")
                    continue
                
                # 检查是否已经是WebP格式
                if file_extension == '.webp':
                    print("文件已经是WebP格式，跳过转换")
                    continue
                
                # 从S3下载图片
                try:
                    response = s3_client.get_object(Bucket=bucket_name, Key=object_key)
                    image_data = response['Body'].read()
                    print(f"成功下载图片，大小: {len(image_data)} bytes")
                except Exception as e:
                    error_msg = f"下载图片失败: {str(e)}"
                    print(f"❌ {error_msg}")
                    print(f"详细错误: {traceback.format_exc()}")
                    failed_files.append({
                        'file': object_key,
                        'error': error_msg,
                        'stage': 'download'
                    })
                    continue
                
                # 转换图片为WebP格式
                try:
                    # 使用PIL打开图片
                    image = Image.open(io.BytesIO(image_data))
                    
                    # 如果图片有透明通道，保持RGBA模式；否则转换为RGB
                    if image.mode in ('RGBA', 'LA'):
                        # 保持透明通道
                        pass
                    elif image.mode == 'P':
                        # 调色板模式，检查是否有透明度
                        if 'transparency' in image.info:
                            image = image.convert('RGBA')
                        else:
                            image = image.convert('RGB')
                    else:
                        # 其他模式转换为RGB
                        image = image.convert('RGB')
                    
                    # 转换为WebP格式
                    webp_buffer = io.BytesIO()
                    image.save(
                        webp_buffer, 
                        format='WebP', 
                        quality=WEBP_QUALITY,
                        optimize=True,
                        method=6  # 最佳压缩方法
                    )
                    webp_data = webp_buffer.getvalue()
                    
                    compression_ratio = ((len(image_data) - len(webp_data)) / len(image_data) * 100)
                    print(f"WebP转换完成，原始大小: {len(image_data)} bytes, WebP大小: {len(webp_data)} bytes")
                    print(f"压缩率: {compression_ratio:.1f}%")
                    
                except Exception as e:
                    error_msg = f"图片转换失败: {str(e)}"
                    print(f"❌ {error_msg}")
                    print(f"详细错误: {traceback.format_exc()}")
                    failed_files.append({
                        'file': object_key,
                        'error': error_msg,
                        'stage': 'conversion'
                    })
                    continue
                
                # 生成输出文件路径
                base_name = os.path.splitext(os.path.basename(object_key))[0]
                directory = os.path.dirname(object_key)
                
                # 确定输出桶
                output_bucket = OUTPUT_BUCKET if OUTPUT_BUCKET else bucket_name
                
                # 生成WebP文件的S3键（默认在原文件目录）
                if OUTPUT_PREFIX:
                    # 如果指定了输出前缀
                    if directory:
                        webp_key = f"{OUTPUT_PREFIX.rstrip('/')}/{directory}/{base_name}.webp"
                    else:
                        webp_key = f"{OUTPUT_PREFIX.rstrip('/')}/{base_name}.webp"
                else:
                    # 默认：在原文件目录创建WebP文件
                    if directory:
                        webp_key = f"{directory}/{base_name}.webp"
                    else:
                        webp_key = f"{base_name}.webp"
                
                # 上传WebP文件到S3
                try:
                    # 获取原始文件的元数据
                    original_metadata = response.get('Metadata', {})
                    
                    # 设置WebP文件的元数据
                    webp_metadata = {
                        'original-format': file_extension[1:],  # 去掉点号
                        'original-size': str(len(image_data)),
                        'webp-size': str(len(webp_data)),
                        'compression-ratio': f"{compression_ratio:.1f}%",
                        'webp-quality': str(WEBP_QUALITY)
                    }
                    
                    # 合并原始元数据
                    webp_metadata.update(original_metadata)
                    
                    s3_client.put_object(
                        Bucket=output_bucket,
                        Key=webp_key,
                        Body=webp_data,
                        ContentType='image/webp',
                        Metadata=webp_metadata
                    )
                    
                    print(f"✅ WebP文件上传成功: s3://{output_bucket}/{webp_key}")
                    
                    # 可选：删除原始文件（通过环境变量控制）
                    if os.environ.get('DELETE_ORIGINAL', 'false').lower() == 'true':
                        s3_client.delete_object(Bucket=bucket_name, Key=object_key)
                        print(f"🗑️ 原始文件已删除: s3://{bucket_name}/{object_key}")
                    
                    processed_files.append({
                        'original': f"s3://{bucket_name}/{object_key}",
                        'webp': f"s3://{output_bucket}/{webp_key}",
                        'compression_ratio': f"{compression_ratio:.1f}%"
                    })
                    
                except Exception as e:
                    error_msg = f"WebP文件上传失败: {str(e)}"
                    print(f"❌ {error_msg}")
                    print(f"详细错误: {traceback.format_exc()}")
                    failed_files.append({
                        'file': object_key,
                        'error': error_msg,
                        'stage': 'upload'
                    })
                    continue
                    
            except Exception as e:
                error_msg = f"处理文件时发生未知错误: {str(e)}"
                print(f"❌ {error_msg}")
                print(f"详细错误: {traceback.format_exc()}")
                failed_files.append({
                    'file': object_key,
                    'error': error_msg,
                    'stage': 'unknown'
                })
        
        # 汇总结果
        total_files = len(event['Records'])
        success_count = len(processed_files)
        failed_count = len(failed_files)
        
        print(f"\n📊 处理汇总:")
        print(f"总文件数: {total_files}")
        print(f"成功转换: {success_count}")
        print(f"失败文件: {failed_count}")
        
        if failed_files:
            print(f"\n❌ 失败文件详情:")
            for failed in failed_files:
                print(f"  - {failed['file']} ({failed['stage']}): {failed['error']}")
        
        # 如果有失败的文件，抛出异常触发Lambda失败通知
        if failed_files:
            raise Exception(f"有 {failed_count} 个文件转换失败，详情请查看日志")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': '图片转换完成',
                'total_files': total_files,
                'processed_files': success_count,
                'failed_files': failed_count,
                'results': processed_files
            }, ensure_ascii=False)
        }
        
    except Exception as e:
        print(f"❌ Lambda函数执行错误: {str(e)}")
        print(f"详细错误: {traceback.format_exc()}")
        
        # 抛出异常，让Lambda的错误处理机制接管
        raise e
