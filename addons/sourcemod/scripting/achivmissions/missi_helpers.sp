int PackInts2(int i1, int i2)
{
	int packed = ((i1 << 16) | i2);
	return packed;
}

void UnpackInts2(int packed, int &i1, int &i2)
{
	i1 = packed >> 16;
	i2 = packed & 32767;
}

int PackInts3(int i1, int i2, int i3)
{
	int packed = i1;
	packed = (packed << 8) + i2;
	packed = (packed << 8) + i3;
	return packed;
}

void UnpackInts3(int packed, int &i1, int &i2, int &i3)
{
	i1 = (packed >> 16) & 255;
	i2 = (packed >> 8) & 255;
	i3 = packed & 255;
}