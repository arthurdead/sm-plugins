#if defined __bit_inc
	#endinput
#endif
#define __bit_inc

stock int pack_2_ints(int i1, int i2)
{
	return ((i1 << 16) | i2);
}

stock int pack_3_ints(int i1, int i2, int i3)
{
	int packed = i1;
	packed = ((packed << 8) + i2);
	packed = ((packed << 8) + i3);
	return packed;
}

stock int pack_4_ints(int i1, int i2, int i3, int i4)
{
	int packed = i1;
	packed = ((packed << 8) + i2);
	packed = ((packed << 8) + i3);
	packed = ((packed << 8) + i4);
	return packed;
}

stock void unpack_2_ints(int packed, int &i1, int &i2)
{
	i1 = (packed >> 16);
	i2 = (packed & 32767);
}

stock void unpack_3_ints(int packed, int &i1, int &i2, int &i3)
{
	i1 = ((packed >> 16) & 255);
	i2 = ((packed >> 8) & 255);
	i3 = (packed & 255);
}

stock void unpack_4_ints(int packed, int &i1, int &i2, int &i3, int &i4)
{
	i1 = ((packed >> 24) & 255);
	i2 = ((packed >> 16) & 255);
	i3 = ((packed >> 8) & 255);
	i4 = (packed & 255);
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
