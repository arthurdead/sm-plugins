#define SHRT_MAX 32767

int PackInts(int i1, int i2)
{
	int packed = ((i1 << 16) | i2);
	return packed;
}

void UnpackInts(int packed, int &i1, int &i2)
{
	i1 = (packed >> 16);
	i2 = (packed & SHRT_MAX);
}