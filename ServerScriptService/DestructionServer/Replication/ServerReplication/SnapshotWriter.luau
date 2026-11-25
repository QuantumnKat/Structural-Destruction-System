--!strict
return function(scratch: buffer, selected: {number}, count: number, timestamp: number, stride: number, trailer: number): buffer
	local payload = buffer.create(count * stride + trailer)
	for index = 1, count do
		buffer.copy(payload, (index - 1) * stride, scratch, (selected[index] - 1) * stride, stride)
	end
	buffer.writef64(payload, count * stride, timestamp)
	buffer.writeu32(payload, count * stride + 8, count)
	return payload
end
