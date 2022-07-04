int digit_count(int i)
{
	int count = 0;
	while(i != 0) {
		i /= 10;
		++count;
	}
	return count;
}