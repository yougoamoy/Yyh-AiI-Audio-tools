-- 测试脚本：验证Rank分布函数是否正确定义
print("测试Rank分布函数...")

-- 测试distribute_random_by_rank函数是否存在
if distribute_random_by_rank then
    print("✓ distribute_random_by_rank函数已正确定义")
else
    print("✗ distribute_random_by_rank函数未定义")
end

-- 测试distribute_discrete_by_rank函数是否存在
if distribute_discrete_by_rank then
    print("✓ distribute_discrete_by_rank函数已正确定义")
else
    print("✗ distribute_discrete_by_rank函数未定义")
end

-- 测试load_rank_config函数是否存在
if load_rank_config then
    print("✓ load_rank_config函数已正确定义")
else
    print("✗ load_rank_config函数未定义")
end

-- 测试get_item_rank函数是否存在
if get_item_rank then
    print("✓ get_item_rank函数已正确定义")
else
    print("✗ get_item_rank函数未定义")
end

-- 测试group_items_by_rank函数是否存在
if group_items_by_rank then
    print("✓ group_items_by_rank函数已正确定义")
else
    print("✗ group_items_by_rank函数未定义")
end

print("\n所有Rank相关函数检查完成。")