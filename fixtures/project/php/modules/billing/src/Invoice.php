<?php

namespace App\Billing;

use App\Dto\UserDto;

/**
 * An invoice raised against a user account.
 *
 * Amounts are held in minor units so that totalling lines never
 * accumulates rounding error.
 */
class Invoice
{
    /** @var array<int, int> */
    private array $lines = [];

    public function __construct(
        public readonly string $number,
        private readonly UserDto $customer,
    ) {
    }

    /**
     * Add a line to the invoice.
     */
    public function addLine(int $minorUnits): void
    {
        $this->lines[] = $minorUnits;
    }

    public function total(): int
    {
        return array_sum($this->lines);
    }

    public function customerName(): string
    {
        return $this->customer->name;
    }
}
