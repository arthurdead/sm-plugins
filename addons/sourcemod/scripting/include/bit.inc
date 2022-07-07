#if defined __bit_inc
	#endinput
#endif
#define __bit_inc

stock void pack_int_in_int(int &buff, int num, int bits, int off)
{
	for(int i = 0; i < bits; ++i) {
		int num_bit = ((num >> i) & 1);
		int buf_pos = (off+i);
		buff = ((buff & ~(1 << buf_pos)) | (num_bit << buf_pos));
	}
}

stock int unpack_int_in_int(int buff, int bits, int off)
{
	int num = 0;

	for(int i = 0; i < bits; ++i) {
		int buf_pos = (off+i);
		int buf_bit = ((buff >> buf_pos) & 1);
		num = ((num & ~(1 << i)) | (buf_bit << i));
	}

	return num;
}

stock int pack_2_ints(int i1, int i2)
{
	int buf = 0;
	pack_int_in_int(buf, i1, 16, 0);
	pack_int_in_int(buf, i2, 16, 16);
	return buf;
}

stock int pack_3_ints(int i1, int i2, int i3)
{
	int buf = 0;
	pack_int_in_int(buf, i1, 8, 0);
	pack_int_in_int(buf, i2, 8, 8);
	pack_int_in_int(buf, i3, 8, 16);
	return buf;
}

stock int pack_4_ints(int i1, int i2, int i3, int i4)
{
	int buf = 0;
	pack_int_in_int(buf, i1, 8, 0);
	pack_int_in_int(buf, i2, 8, 8);
	pack_int_in_int(buf, i3, 8, 16);
	pack_int_in_int(buf, i4, 8, 24);
	return buf;
}

stock void unpack_2_ints(int buf, int &i1, int &i2)
{
	i1 = unpack_int_in_int(buf, 16, 0);
	i2 = unpack_int_in_int(buf, 16, 16);
}

stock void unpack_3_ints(int buf, int &i1, int &i2, int &i3)
{
	i1 = unpack_int_in_int(buf, 8, 0);
	i2 = unpack_int_in_int(buf, 8, 8);
	i3 = unpack_int_in_int(buf, 8, 16);
}

stock void unpack_4_ints(int buf, int &i1, int &i2, int &i3, int &i4)
{
	i1 = unpack_int_in_int(buf, 8, 0);
	i2 = unpack_int_in_int(buf, 8, 8);
	i3 = unpack_int_in_int(buf, 8, 16);
	i4 = unpack_int_in_int(buf, 8, 24);
}

stock void pack_int_in_str(int val, char[] str, int off=0)
{
	str[off+0] = ((val & 255)+1);
	str[off+1] = (((val >> 8) & 255)+1);
	str[off+2] = (((val >> 16) & 255)+1);
	str[off+3] = (((val >> 24) & 255)+1);
	str[off+4] = '\0';
}

stock int unpack_int_in_str(char[] str, int off=0)
{
	int ret = (str[off+3]-1);
	ret = ((ret << 8) + (str[off+2]-1));
	ret = ((ret << 8) + (str[off+1]-1));
	ret = ((ret << 8) + (str[off+0]-1));
	return ret;
}

stock int read_int_from_data(const char[] data, int bits, int &offset, int &idx)
{
	int num = 0;

	for(int i = 0; i < bits; ++i) {
		int buf_bit = ((data[idx] >> offset) & 1);
		num = ((num & ~(1 << i)) | (buf_bit << i));
		if(++offset == 8) {
			++idx;
			offset = 0;
		}
	}

	return num;
}

stock void store_int_in_data(char[] data, int num, int bits, int &offset, int &idx)
{
	for(int i = 0; i < bits; ++i) {
		int num_bit = ((num >> i) & 1);
		data[idx] = ((data[idx] & ~(1 << offset)) | (num_bit << offset));
		if(++offset == 8) {
			++idx;
			offset = 0;
		}
	}
}
